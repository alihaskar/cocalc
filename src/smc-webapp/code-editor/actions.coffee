###
Editor Actions
###

WIKI_HELP_URL   = "https://github.com/sagemathinc/cocalc/wiki/editor"  # TODO -- write this

immutable      = require('immutable')
underscore     = require('underscore')
{Actions}      = require('../smc-react')
misc           = require('smc-util/misc')
keyboard       = require('./keyboard')
copypaste      = require('../copy-paste-buffer')
convert_to_pdf = require('./convert-to-pdf')
browser_print  = require('./browser-print')
tree_ops       = require('./tree-ops')

class exports.Actions extends Actions
    _init: (project_id, path, syncstring, store) =>
        @project_id = project_id
        @path       = path
        @_syncstring = syncstring
        @store      = store

        @_save_local_view_state = underscore.debounce((=>@__save_local_view_state?()), 1500)

        @_init_has_unsaved_changes()
        @setState
            local_view_state : @_load_local_view_state()

        @_syncstring.once('init', @_syncstring_metadata)
        @_syncstring.on('metadata-change', @_syncstring_metadata)

        @_syncstring.on('change', @_syncstring_change)
        @_syncstring.on('init', @_syncstring_change)

        @_syncstring.once('load-time-estimate', (est) => @setState(load_time_estimate: est))

    close: =>
        if @_state == 'closed'
            return
        @_state = 'closed'
        @__save_local_view_state?()
        delete @_save_local_view_state
        if @_key_handler?
            @redux.getActions('page').erase_active_key_handler(@_key_handler)
            delete @_key_handler
        if @_syncstring?
            # Do not want to loose the very last change user made!
            @set_syncstring_to_codemirror()
            @_syncstring._save()
            @_syncstring.close()
            delete @_syncstring

    __save_local_view_state: =>
        local_view_state = @store.get('local_view_state')
        if local_view_state? and localStorage?
            localStorage[@name] = JSON.stringify(local_view_state)

    _load_local_view_state: =>
        x = localStorage[@name]
        if x?
            local_view_state = immutable.fromJS(JSON.parse(x))
        local_view_state ?= immutable.Map()

        if not local_view_state.has('version') # may use to deprecate in case we change format.
            local_view_state = local_view_state.set('version', 1)

        if not local_view_state.has("font_size")
            font_size = @redux.getStore('account')?.get('font_size') ? 14
            local_view_state = local_view_state.set('font_size', font_size)

        frame_tree = local_view_state.get('frame_tree')
        if not frame_tree?
            frame_tree = @_default_frame_tree()
        else
            frame_tree = tree_ops.assign_ids(frame_tree)
            frame_tree = tree_ops.ensure_ids_are_unique(frame_tree)
        local_view_state = local_view_state.set('frame_tree', frame_tree)

        active_id = local_view_state.get('active_id')
        if not active_id? or not tree_ops.is_leaf_id(frame_tree, active_id)
            local_view_state = local_view_state.set('active_id', tree_ops.get_some_leaf_id(frame_tree))

        return local_view_state

    set_local_view_state: (obj, update_visible=true) =>
        if @_state == 'closed'
            return
        # Set local state related to what we see/search for/etc.
        local = @store.get('local_view_state')
        for key, value of obj
            local = local.set(key, immutable.fromJS(value))
        @setState
            local_view_state : local
        @_save_local_view_state()
        return

    set_active_id: (active_id) =>
        @tree_ops = tree_ops
        local = @store.get('local_view_state')
        if tree_ops.is_leaf_id(local?.get('frame_tree'), active_id)
            @setState(local_view_state : @store.get('local_view_state').set('active_id', active_id))
            @_save_local_view_state()
        return

    _tree_op: (op, args...) =>
        local = @store.get('local_view_state')
        t0    = local?.get('frame_tree')
        if not t0?
            return
        f = tree_ops[op]
        if not f?
            throw Error("unknown tree op '#{op}'")
        t1 = f(t0, args...)
        if t1 != t0
            if op == 'delete_node'
                if not tree_ops.is_leaf_id(t1, local.get('active_id'))
                    local = local.set('active_id',  tree_ops.get_some_leaf_id(t1))
                if not tree_ops.is_leaf_id(t1, local.get('full_id'))
                    local = local.delete('full_id')
            @setState(local_view_state : local.set('frame_tree', t1))
            @_save_local_view_state()
        return

    _default_frame_tree: =>
        frame_tree = immutable.fromJS
            type : 'cm'
            path : @path
        frame_tree = tree_ops.assign_ids(frame_tree)
        frame_tree = tree_ops.ensure_ids_are_unique(frame_tree)
        return frame_tree

    set_frame_tree: (obj) =>
        @_tree_op('set', obj)

    reset_frame_tree: =>
        local = @store.get('local_view_state')
        local = local.set('frame_tree', @_default_frame_tree())
        @setState(local_view_state: local)
        @_save_local_view_state()
        return

    close_frame: (id) =>
        @_tree_op('delete_node', id)

    split_frame: (direction, id) =>
        @_tree_op('split_leaf', id ? @store.getIn(['local_view_state', 'active_id']), direction)

    set_frame_full: (id) =>
        local   = @store.get('local_view_state')
        @setState(local_view_state : local.set('full_id', id).set('active_id', id))
        @_save_local_view_state()

    save_scroll_position: (id, info) =>
        @set_frame_tree(id:id, scroll:info)

    enable_key_handler: =>
        if @_state == 'closed'
            return
        @_key_handler ?= keyboard.create_key_handler(@)
        @redux.getActions('page').set_active_key_handler(@_key_handler)

    disable_key_handler: =>
        @redux.getActions('page').erase_active_key_handler(@_key_handler)

    _init_has_unsaved_changes: =>  # basically copies from tasks/actions.coffee -- opportunity to refactor
        do_set = =>
            @setState
                has_unsaved_changes     : @_syncstring?.has_unsaved_changes()
                has_uncommitted_changes : @_syncstring?.has_uncommitted_changes()
        f = =>
            do_set()
            setTimeout(do_set, 3000)
        @set_save_status = underscore.debounce(f, 500, true)
        @_syncstring.on('metadata-change', @set_save_status)
        @_syncstring.on('connected',       @set_save_status)

    _syncstring_metadata: =>
        read_only = @_syncstring.get_read_only()
        if read_only != @store.get('read_only')
            @setState(read_only: read_only)

    _syncstring_change: (changes) =>
        if not @store.get('is_loaded')
            @setState(is_loaded: true)
        @set_save_status?()

    delete_trailing_whitespace: =>
        cm = @cm
        if not cm?
            return
        omit_lines = {}
        @_syncstring.get_cursors()?.map (x, _) =>
            x.get('locs')?.map (loc) =>
                y = loc.get('y')
                if y?
                    omit_lines[y] = true
        console.log omit_lines
        cm.delete_trailing_whitespace(omit_lines:omit_lines)

    save: (explicit) =>
        @setState(has_unsaved_changes:false)
        # TODO: what about markdown, where do not want this...
        # and what about multiple syncstrings...
        # TODO: Maybe just move this to some explicit menu of actions, which also includes several other formatting actions.
        # Doing this automatically is fraught with error, since cursors aren't precise...
        if explicit and @redux.getStore('account')?.getIn(['editor_settings', 'strip_trailing_whitespace'])
            @delete_trailing_whitespace()
        @_syncstring?.save_to_disk =>
            @set_save_status()
            # do it again.
            @_syncstring?.save_to_disk =>
                @set_save_status()

    time_travel: =>
        @redux.getProjectActions(@project_id).open_file
            path       : misc.history_path(@path)
            foreground : true

    help: =>
        window.open(WIKI_HELP_URL, "_blank").focus()

    undo: =>
        # TODO: do we need explicit exit of undo mode anywhere??!
        @_syncstring?.undo()

    redo: =>
        @_syncstring?.redo()

    change_font_size: (delta, id) =>
        local      = @store.getIn('local_view_state')
        id        ?= local.get('active_id')
        font_size  = tree_ops.get_node(local.get('frame_tree'), id)?.get('font_size')
        if not font_size?
            font_size = @redux.getStore('account')?.get('font_size') ? 14
        font_size  += delta
        if font_size < 2
            font_size = 2
        @set_frame_tree(id:id, font_size:font_size)

    increase_font_size: (id) =>
        @change_font_size(1, id)

    decrease_font_size: (id) =>
        @change_font_size(-1, id)

    set_cm: (cm, id) =>
        if id
            @_cm ?= {}
            @_cm[id] = cm
        @cm = cm
        @set_codemirror_to_syncstring()

    _active_cm: =>
        return @_cm?[local_view_state.get('active_id')]

    syncstring_save: =>
        @_syncstring?.save()
        @set_save_status()

    set_syncstring_to_codemirror: =>
        if not @cm? or not @_syncstring?
            return
        @_syncstring.from_str(@cm.getValue())

    set_codemirror_to_syncstring: =>
        if not @cm? or not @_syncstring?
            return
        @cm.setValueNoJump(@_syncstring.to_str())
        @set_save_status()

    exit_undo_mode: =>
        @_syncstring?.exit_undo_mode()

    # per-session sync-aware undo
    undo: =>
        if not @cm?
            return
        if not @_syncstring.in_undo_mode()
            @set_syncstring_to_codemirror()
        value = @_syncstring.undo().to_str()
        @cm.setValueNoJump(value)
        @set_syncstring_to_codemirror()
        @_syncstring_save()

    # per-session sync-aware redo
    redo: =>
        if not @cm?
            return
        if not @_syncstring.in_undo_mode()
            return
        doc = @_syncstring.redo()
        if not doc?
            # can't redo if version not defined/not available.
            return
        value = doc.to_str()
        @cm.setValueNoJump(value)
        @set_syncstring_to_codemirror()
        @_syncstring_save()

    find: =>
        @cm?.execCommand('find')

    find_next: =>
        @cm?.execCommand('findNext')

    find_prev: =>
        @cm?.execCommand('findPrev')

    replace: =>
        @cm?.execCommand('replace')

    goto_line: =>
        @cm?.execCommand('jumpToLine')

    cut: =>
        copypaste.set_buffer(@cm?.getSelection())
        @cm?.replaceSelection('')

    copy: =>
        copypaste.set_buffer(@cm?.getSelection())

    paste: =>
        @cm?.replaceSelection(copypaste.get_buffer())

    print: =>
        @setState(printing: true)
        convert_to_pdf.convert
            path  : @path
            cb    : (err, pdf) =>
                @setState(printing: false)
                if err
                    @setState(error: err)
                else
                    browser_print.print(pdf:pdf)

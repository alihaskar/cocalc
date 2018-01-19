###
Toggle to minimize display of a task (just show first part or everything)
###

{React, rclass, rtypes}  = require('../smc-react')

{Icon, Tip} = require('../r_misc')

exports.MinToggle = rclass
    propTypes :
        actions   : rtypes.object
        task_id   : rtypes.string
        full_desc : rtypes.bool
        has_body  : rtypes.bool

    shouldComponentUpdate: (next) ->
        return @props.full_desc != next.full_desc or @props.has_body != next.has_body

    render_toggle: ->
        if not @props.has_body
            return <Icon name={'caret-right'} />
        if @props.full_desc
            name = 'caret-down'
        else
            name = 'caret-right'
        return <Icon name={name} />

    toggle_state: ->
        @props.actions.toggle_full_desc(@props.task_id)

    render: ->
        if not @props.actions?  # no support for toggling (e.g., history view)
            return <span/>
        toggle = @render_toggle()
        if @props.has_body
            if @props.full_desc
                title = 'Show only up to first blank line'
            else
                title = 'Show full description'
            <Tip title={title} delayShow={1000}>
                <div onClick={@toggle_state} style={fontSize:'17pt', color:'#888'}>
                    {toggle}
                </div>
            </Tip>
        else
            <span />
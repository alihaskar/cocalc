###
Complete 100% top-level react rewrite of CoCalc.
###

fullscreen = require('./fullscreen')

# FUTURE: This is needed only for the old non-react editors; will go away.
html = require('./console.html') + require('./editor.html') + require('./jupyter.html') + require('./sagews/interact.html') + require('./sagews/3d.html') + require('./sagews/d3.html')
$('body').append(html)

# deferred initialization of buttonbars until after global imports -- otherwise, the sagews sage mode bar might be blank
{init_buttonbars} = require('./buttonbar')
init_buttonbars()

# Load/initialize Redux-based react functionality
{redux} = require('./app-framework')

# Initialize server stats redux store
require('./redux_server_stats')

# Systemwide notifications that are broadcast to all users (or set by admins)
require('./system_notifications')

require('./landing-actions')

# Makes some things work. Like the save button
require('./jquery_plugins')

# Initialize app stores, actions, etc.
require('./init_app')

# Initialize the account store.
require('./account')

notifications = require('./notifications')
if not fullscreen.COCALC_MINIMAL
    notifications.init(redux)

require('./widget-markdown-input/main').init(redux)

# Feature must be loaded before account and anything that might use cookies or localStorage,
# but after app-framework and the basic app definition.
{IS_MOBILE, isMobile} = require('./feature')

if IS_MOBILE and not isMobile.tablet()
    # Cell-phone version of site, with different
    # navigation system for selecting projects and files.
    mobile = require('./mobile_app')
    mobile.render()
else
    desktop = require('./desktop_app')
    desktop.render()

$(window).on('beforeunload', redux.getActions('page').check_unload)

# Should be loaded last -- this checks the url and opens up the relevant page, etc.
require('./last')

require('./crash')

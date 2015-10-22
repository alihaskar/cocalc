require('coffee-script/register') /* so we can require coffeescript */
require('coffee-cache')  /* so coffeescript doesn't get recompiled every time we require it */

exports.compute = require('./compute.coffee')
exports.sqlite  = require('./sqlite.coffee')
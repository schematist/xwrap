// require coffee if possible; js otherwise
try {
  try { require('coffee-script/register'); } catch (e) {}  
  xwrap = require('./src/xwrap');
}
catch (e) {
  if(e.message.indexOf("Cannot find module") != -1 
      && (e.message.indexOf('./src/index') != -1 
        || e.message.indexOf('coffee-script/register') != -1))
    xwrap = require('./lib/xwrap');
  else
    throw e;
}
module.exports = xwrap;
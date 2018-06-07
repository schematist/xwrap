// require coffee if possible; js otherwise
try {
  require('coffeescript/register');
  xwrap = require('./src/xwrap');
}
catch (e) {
  try {
    xwrap = require('./lib/xwrap');
  } catch (e) {
    throw e;
  }
}
module.exports = xwrap;

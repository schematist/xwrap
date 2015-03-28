// require coffee if possible; js otherwise
try {
  require('coffee-script/register');  
  schematist = require('./src/index');
}
catch (e) {
  if(e.message.indexOf("Cannot find module") != -1 
      && (e.message.indexOf('./src/index') != -1 
        || e.message.indexOf('coffee-script/register') != -1))
    schematist = require('./lib/index');
  else
    throw e;
}
module.exports = schematist;
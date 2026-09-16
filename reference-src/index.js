// for loading .coffee files
require('coffeescript').register();

exports.sections = [
  require('./basics.coffee'),
  require('./methods.coffee'),
  require('./data-structure.coffee')
];

exports.version = '2.0.0-pre';

exports.system = require('./system.coffee');
exports.admin = require('./admin.coffee');

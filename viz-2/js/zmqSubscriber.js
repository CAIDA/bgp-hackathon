var zmq = require('zmq');
var config = require('./config');

var zmqSubscriber = function() {

    this.subscribeStream = function(subMode, callback) {
        var url = 'tcp://' + config.zmq_host + ':' + config.zmq_port.toString();
        console.log('Subscribing routes from publisher ' + url);

        var socket = zmq.socket('sub');
        if (subMode.type == 'all') {
            console.log('subscribing all routes')
            socket.subscribe('r-');
        } else if (subMode.type == 'router') {
            console.log('subscribing routes for router ' + subMode.value);
            socket.subscribe('r-' + subMode.value);
        } else if (subMode.type == 'prefix') {
            console.log('subscribing routes for prefix ' + subMode.value);
            socket.subscribe('p-' + subMode.value);
        } else {
            throw 'Unknown subscription mode ' + subMode.type;
        }

        socket.on('message', function (callback, filter, msg) {
            callback(config.eventsNames.update, JSON.parse(msg));
        }.bind(this, callback));
        socket.connect(url);

        return socket;
    };

};

/*
var connector = new zmqSubscriber()
connector.subscribeStream(
  {type: 'router', value: '195.208.209.109'},
  function(evt, data) { console.log(data); },
);
*/

module.exports = zmqSubscriber;

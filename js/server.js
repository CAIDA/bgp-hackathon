/**
 * Copyright 2016 - mcandela
 * Date: 06/02/16
 * Time: 22:44
 * See LICENSE.txt for information about the license.
 */
var config = require('./config');
var server = require('http').createServer();
var io = require('socket.io')(server);

var mysqlConnector = require('./mysqlConnector');
var zmqSubscriber = require('./zmqSubscriber');
var subscriber = new zmqSubscriber();

var checkParameters = function(userParams) {
    var error = true;
    if (!userParams.asn && !userParams.prefix){
        error = "ans or prefix are needed";
    }
    return error;
};


io.on('connection', function (socket) {
    var emit, onError, zmqSocket;
    var connector = new mysqlConnector();

    emit = function(type, message) {
        socket.emit(type, message);
    };

    onError = function(error) {
        console.log(error);
        socket.emit(config.eventsNames.error, error);
    };

    socket.on('disconnect', function() {
        zmqSocket && zmqSocket.close();
        zmqSocket = null;
    });

    socket.on(config.eventsNames.subscribe, function (userParams, cb) {
        var type, dataChecking;

        dataChecking = checkParameters(userParams);
        if (dataChecking === true){
            type = (userParams.asn) ? "asn" : "prefix";

            if (type == "asn"){
                connector.getDumpByAS(userParams.asn, emit, onError);
            } else {
                connector.getDumpByPrefix(userParams.prefix, emit, onError);
            }

            console.log({
                type: type, // or 'prefix' or 'all'
                value: (type == "prefix") ? userParams.prefix : userParams.asn
            });
            zmqSocket = subscriber.subscribeStream({
                type: type, // or 'prefix' or 'all'
                value: (type == "prefix") ? userParams.prefix : userParams.asn
            }, emit);
        } else {
            onError(dataChecking);
        }
    });
});


server.listen(config.port);


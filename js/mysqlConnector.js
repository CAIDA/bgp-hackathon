var mysql      = require('mysql');
var config      = require('./config');

var mysqlConnector = function (){
    var connection, table;

    connection = mysql.createConnection({
        host     : config.host,
        user     : config.user,
        password : config.password,
        database : config.database
    });

    table = config.table;

    // connection.connect();

    this.getDumpByPrefix = function (prefix, callback, onError){
        var query;

        query = 'SELECT value from ' + table + ' WHERE prefix = \"' + prefix + '\"';
        this._retrieveDump(query, callback, onError);
    };

    this.getDumpByAS = function (asn, callback, onError){
        var query;

        query = 'SELECT value from ' + table + ' WHERE origin_asn = \"' + asn + '\"';
        this._retrieveDump(query, callback, onError);
    };

    this._retrieveDump = function (query, callback, onError){
        connection.query(query, function(error, rows, fields) {
            if (!error) {
                for (var line=0; line < rows.length; line++) {
                    if (rows[line] && rows[line].value) {
                        var message = JSON.parse(rows[line].value);
                        message.type = "dump";
                        callback(config.eventsNames.dump, message);
                    }
                }

                callback(config.eventsNames.endOfDump, null);

            } else {
                onError(error);
            }
        });

        this.close();
    };

    this.close = function () {
        connection.end();
    }
};

module.exports = mysqlConnector;






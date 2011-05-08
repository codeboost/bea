/**
 * Parser arguments array
 * https://github.com/kof/node-argsparser.git
 * @param {Array} args optional arguments arrray.
 * @return {Object} opts key value hash.
 * @export
 */
exports.parse = function(args) {
    // args is optional, default is process.argv
    args = args || process.argv;

    var opts = {},
        curSwitch;

    args.forEach(function(arg) {
        var curValType = typeof opts[curSwitch];
        // its a switch
        if (/^(-|--)/.test(arg)) {
            opts[arg] = true;
            curSwitch = arg;
        // this arg is some data
        } else if (curSwitch) {
            if (arg === 'false') {
                arg = false;
            } else if (arg === 'true') {
                arg = true;
            } else if (!isNaN(arg)) {
                arg = Number(arg);
            }

            if (curValType === 'boolean') {
                opts[curSwitch] = arg;
            } else if (curValType === 'string') {
                opts[curSwitch] = [opts[curSwitch], arg];
            } else {
                opts[curSwitch].push(arg);
            }
        } else {
            opts[arg] = true;
            curSwitch = arg;
        }
    });

    return opts;
};
var https = require('https');
exports.handler = (event, context) => {

console.log("MY :"+event.detail.name)
var env_name=event.detail.name
env_name=env_name.replace(/\//,"");
env_name=env_name.replace("/ENV_REVISION","");
env_name=env_name.replace(/\//g,"-");
var JENKINS_JOB=env_name+'-env'
console.log("MY :"+env_name)
//console.log("ENVIRONMENT VARIABLES\n" + JSON.stringify(process.env, null, 2))
console.info("EVENT\n" + JSON.stringify(event, null, 2))
//console.warn("Event not processed.")
var params = {
host: "jenkins.bdswiss.com",
path: "/job/"+JENKINS_JOB+"/build?token=b026324c6904b2a9cb4b88d6d61c81d1",
method: 'GET',
headers: {
'Authorization': 'Basic ' + new Buffer.from("auto" + ':' + "11877aca45c8fa2808880a5a1469375b03").toString('base64')
} 
};

var req = https.request(params, function(res) {
let data = '';
console.log('STATUS: ' + res.statusCode);
res.setEncoding('utf8');
});
req.end();

return context.logStreamName
}

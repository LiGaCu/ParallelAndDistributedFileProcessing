"use strict";

const express = require('express');
const cors = require('cors');
const path = require('path');

const fs = require('fs');
const upload_dir = './uploads', uploadRst_dir = './uploadRst';
if (!fs.existsSync(upload_dir)){
    fs.mkdirSync(upload_dir);
}
if (!fs.existsSync(uploadRst_dir)){
    fs.mkdirSync(uploadRst_dir);
}

const multer = require("multer");
const uploadStorage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, upload_dir)
    },
    filename: function (req, file, cb) {
        const uniquePrefix = Date.now();
        cb(null, `${uniquePrefix}-${file.originalname}`)
    }
})
const resultStorage = multer.diskStorage({
    destination: function (req, file, cb) {
        cb(null, uploadRst_dir)
    },
    filename: function (req, file, cb) {
        const uniquePrefix = Date.now();
        cb(null, `${uniquePrefix}-${file.originalname}`)
    }
})
const upload = multer({ storage: uploadStorage });
const uploadRst = multer({ storage: resultStorage });

const https = require('https');
const privateKey  = fs.readFileSync('/etc/letsencrypt/live/server.lijiatong1997.com/privkey.pem', 'utf8');
const certificate = fs.readFileSync('/etc/letsencrypt/live/server.lijiatong1997.com/fullchain.pem', 'utf8');
const credentials = {key: privateKey, cert: certificate};

const pendingQueue = [];
const computeNodeMap = { lijiaton: {}, jiatong: {} };

const app = express();
app.use(cors());

app.use(express.json());
app.use(express.urlencoded({ extended: false }));

function taskToNode(nodeTask, pendingTask) {
    return new Promise((resolve, rejects) =>{
        let nodeRes = nodeTask.nodeRes;
        nodeTask.nodeRes = null;
        nodeRes.download(pendingTask[1], pendingTask[0],  function (err) {
            if (err) {
                rejects(err);
            } else {
                nodeTask.filename = pendingTask[0];
                nodeTask.filepath = pendingTask[1];
                nodeTask.clientRes = pendingTask[2];
                resolve(pendingQueue.shift());
            }
        });
    });
}

app.post('/upload', upload.single('uploaded_file'), async function(req, res) {
    pendingQueue.push([req.file.filename, req.file.path, res]);
    console.log(`Received pending file: ${req.file.filename}`);
    for (let [key, nodeTask] of Object.entries(computeNodeMap)) {
        if (nodeTask.nodeRes) {
            let pendingTask = pendingQueue[0];
            let stopFlag = false;
            await taskToNode(nodeTask, pendingTask).then(()=> {stopFlag = true;}).catch(()=> {stopFlag = false;});
            if (stopFlag) { return; }
        }
    }
});

app.get('/nodeRegister/:nodeuser', function(req, res) {
    console.log(`Received node register request: ${req.params.nodeuser}`);
    if (req.params.nodeuser && (req.params.nodeuser in computeNodeMap)) {
        let nodeTask = computeNodeMap[req.params.nodeuser];
        if (nodeTask.filename) {
            // failed task recovery
            nodeTask.nodeRes = null;
            res.download(nodeTask.filepath, nodeTask.filename);
            return;
        }
        nodeTask.nodeRes = res;
        if (pendingQueue.length) {
            let pendingTask = pendingQueue[0];
            taskToNode(nodeTask, pendingTask);
        }
    }
});

app.post('/nodeReturn/:nodeuser', uploadRst.single('processed_file'), function(req, res) {
    const originalname = req.file.filename.substring(req.file.filename.indexOf('-')+1);
    console.log(`Received processed file: ${originalname}`);
    if (req.params.nodeuser && (req.params.nodeuser in computeNodeMap)) {
        let nodeTask = computeNodeMap[req.params.nodeuser];
        nodeTask.clientRes.sendFile(path.join(__dirname, req.file.path));
        nodeTask.filename = null;
        nodeTask.filepath = null;
        nodeTask.clientRes = null;
        res.status(200).end('Result Recieved');
        return;
    }
    res.status(204).end();
});

// Start the server
const HTTPSPORT = process.env.HTTPSPORT || 443;

const httpsServer = https.createServer(credentials, app);
httpsServer.listen(HTTPSPORT, function() {
    console.log(`Backend Application listening at http://localhost:${HTTPSPORT}`);
});
const fs = require('fs');
const path = require('path');
const electron = require('electron');



class App {
  constructor () {
    this.client = null;
    this.server = null;
    this.appInstance = null;
  }

  log (...args) {
    console.log(...args);
  }

  // createServer (port) {
  //   if (this.server) {
  //     this.log('server already created');
  //     return;
  //   }

  //   this.server = new ws.Server({port: port});
  //   this.server.on('connection', (ws) => {
  //     this.log('client connected');
  //     this.initClient(ws);
  //   });
  //   this.server.on('error', (e) => {
  //     this.log('server error:', e.message);
  //   });
  //   this.server.on('close', () => {
  //     this.log('server closed');
  //     this.server = null;
  //   });
  //   this.log('server listening on port:', port);
  // }

  // initClient (client) {
  //   if (this.client) {
  //     this.log('client already created');
  //     return;
  //   }

  //   client.on('error', (e) => {
  //     this.log('client error:', e.message);
  //   });
  //   client.on('messge', (message) => {
  //     this.handleMesssge(message);
  //   });
  //   client.on('close', () => {
  //     this.log('client closed');
  //     this.client = null;
  //   });

  //   this.client = client;
  // }

  handleMesssge (message) {
    this.log('message:', message);
  }

  start () {
    console.info('webview start', process.argv);
    let params = {};
    let web = ""
    let port = 10086;
    process.argv.forEach((val, index) => {
      if (val.startsWith('--wid=')) {
        web = val.replace('--wid=', '');
      }
      if (val.startsWith('--port=')) {
        port = parseInt(val.replace('--port=', ''));
      }
      
      let match = val.match(/^--data-([^=]+)=(.*)/);
      if (match) {
        params[match[1]] = match[2];
      }
    });


    switch (web) {
      case 'feishu':
        let Feishu = require('./app/feishu/feishu.js');
        this.appInstance = new Feishu(this, params);
        break;
    }
  }
}

new App().start();
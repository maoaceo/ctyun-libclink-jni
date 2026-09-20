const electron = require('electron');

function response (code) {
  electron.ipcRenderer.send('feishu:response', {
    code: code,
  });
}

function main () {
  document.getElementById('title').addEventListener('click', () => {
    console.log('click title');
    response('test');
  });
}

main();
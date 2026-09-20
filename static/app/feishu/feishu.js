const fs = require('fs');
const path = require('path');
const electron = require('electron');
const cp = require('child_process');

class Feishu {
  constructor (app, params = {}) {
    this.app = app;
    this.params = params;
    this.win = null;
    this.start();
  }

  // registerIpc () {
  //   electron.ipcMain.on('feishu:response', (event, args) => {
  //     this.app.log('feishu response:', args);
  //     cp.exec(`${this.params.app} --feishuToken=${args.code}`, (err, stdout) => {
  //       console.log('exec:', err, stdout);
  //       this.win.close();
  //     });
  //   });
  // }

  async start () {
    this.app.log('feishu start');
    await electron.app.whenReady();
    // this.registerIpc();
    this.win = new electron.BrowserWindow({
      width: 720,
      height: 635,
      autoHideMenuBar: true,
      webPreferences: {
        nodeIntegration: true,
        contextIsolation: false,
      }
    });

    this.win.setMenu(null);

    // 清除浏览器缓存，不保存登录态
    try {
      const ses = this.win.webContents.session;
      await ses.clearStorageData({
        storages: [
          'cookies',
          'localstorage',
          'cachestorage',
          'indexdb',
          'serviceworkers',
          'websql',
        ],
      });
      await ses.clearCache();
      if (typeof ses.clearAuthCache === 'function') {
        await ses.clearAuthCache();
      }
    } catch (error) {
      this.app.log('Error clearing session data:', error.message);
    }

    // this.win.loadFile(path.join(__dirname, `feishuQrCode.html`), {
    //   query: this.params
    // });
    let url = this.params.url;
    console.log("electron webview url:", url);
    this.win.loadURL(url);
    
    // 监听URL变化
    this.win.webContents.on('did-navigate', (event, newUrl) => {
      this.app.log('URL changed:', newUrl);
      this.checkCodeInUrl(newUrl);
    });
    
    // 监听窗口关闭
    this.win.on('closed', () => {
      this.app.log('feishu window closed');
      this.win = null;
      electron.app.exit(0);
    });
  }
  
  // 检查URL中是否包含code参数（兼容query和hash）
  checkCodeInUrl(url) {
    try {
      const urlObj = new URL(url);
      const hash = urlObj.hash.startsWith('#') ? urlObj.hash.slice(1) : urlObj.hash;
      const hashParams = new URLSearchParams(hash);
      const code =
        urlObj.searchParams.get(this.params.authCodeParamName) ||
        hashParams.get(this.params.authCodeParamName)
      if (code) {
        this.app.log('Found code in URL:', code);
        // 传递code到qml上层
        cp.exec(`"${this.params.app}" --feishuCode=${code}`, (err, stdout) => {
          console.log('exec:', err, stdout);
          this.win.close();
        });
      }
    } catch (error) {
      this.app.log('Error parsing URL:', error.message);
    }
  }
}

module.exports = Feishu;

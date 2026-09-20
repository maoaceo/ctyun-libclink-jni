#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
天翼云电脑 官方电源管控模块 (对齐 ctyun-dashboard 签名与 Triple Link 开机链路)
"""

import sys
import os
import time
import json
import hashlib
import sqlite3
import glob
import urllib.request
import urllib.parse
import urllib.error

def get_sqlite_path():
    dbs = glob.glob(os.path.expanduser('~/.local/share/CtyunClouddeskPublic/QML/OfflineStorage/Databases/*.sqlite'))
    return dbs[0] if dbs else None

def get_auth_info():
    """从本地官方客户端提取鉴权凭证"""
    db = get_sqlite_path()
    if not db or not os.path.exists(db):
        return None
    
    info = {
        "userId": "18804858",
        "tenantId": "14",
        "deviceCode": "FA:16:3E:AD:95:17",
        "secretKey": "",
        "token": "",
        "userAccount": ""
    }
    
    try:
        conn = sqlite3.connect(db)
        cur = conn.cursor()
        
        cur.execute("SELECT name, value FROM data WHERE name = 'device_code' OR name = 'device_uuid'")
        for r in cur.fetchall():
            val = str(r[1]).strip('"').strip("'")
            if val:
                info["deviceCode"] = val
                break
                
        cur.execute("SELECT value FROM data WHERE name = 'advertiseUserId'")
        r = cur.fetchone()
        if r and r[0]:
            info["userId"] = str(r[0]).strip('"').strip("'")
            
        cur.execute("SELECT value FROM data WHERE name = 'advertiseUserAccount'")
        r = cur.fetchone()
        if r and r[0]:
            info["userAccount"] = str(r[0]).strip('"').strip("'")
            
        cur.execute("SELECT value FROM data WHERE name = 'crashAccountData'")
        r = cur.fetchone()
        if r and r[0]:
            try:
                acc = json.loads(r[0])
                if acc.get("tenantId"):
                    info["tenantId"] = str(acc.get("tenantId"))
                if acc.get("userId"):
                    info["userId"] = str(acc.get("userId"))
                if acc.get("token"):
                    info["token"] = str(acc.get("token"))
                if acc.get("secretKey"):
                    info["secretKey"] = str(acc.get("secretKey"))
            except Exception:
                pass
                
        conn.close()
    except Exception as e:
        pass
        
    return info

def get_signed_headers(auth_info, device_type="60", version="103020001"):
    """
    对齐 ctyun-dashboard getSignedHeaders 官方 MD5 签名计算
    sig = MD5(deviceType + timestamp + tenantId + timestamp + userId + version + secretKey)
    """
    ts = str(int(time.time() * 1000))
    tenant_id = auth_info.get("tenantId", "14")
    user_id = auth_info.get("userId", "18804858")
    secret_key = auth_info.get("secretKey", "")
    device_code = auth_info.get("deviceCode", "FA:16:3E:AD:95:17")
    
    raw_sig_str = f"{device_type}{ts}{tenant_id}{ts}{user_id}{version}{secret_key}"
    sig = hashlib.md5(raw_sig_str.encode('utf-8')).hexdigest()
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/137.0.0.0',
        'ctg-devicetype': device_type,
        'ctg-version': version,
        'ctg-devicecode': device_code,
        'ctg-userid': user_id,
        'ctg-tenantid': tenant_id,
        'ctg-timestamp': ts,
        'ctg-requestid': ts,
        'ctg-signaturestr': sig,
        'referer': 'https://pc.ctyun.cn/',
        'Content-Type': 'application/x-www-form-urlencoded'
    }
    
    if auth_info.get("token"):
        headers['Cookie'] = f"token={auth_info['token']}"
        
    return headers

def send_operate(desktop_id, operation_type, auth_info):
    """向官方机房下发单次 operate 电源指令"""
    url = "https://desk.ctyun.cn:8810/api/desktop/client/operate"
    headers = get_signed_headers(auth_info)
    data = urllib.parse.urlencode({
        "desktopId": str(desktop_id),
        "operationType": str(operation_type)
    }).encode('utf-8')
    
    req = urllib.request.Request(url, data=data, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            res_str = resp.read().decode('utf-8')
            return json.loads(res_str)
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode('utf-8'))
        except Exception:
            return {"code": e.code, "msg": str(e)}
    except Exception as e:
        return {"code": -1, "msg": str(e)}

def control_power(desktop_id, action="poweron"):
    """
    对齐 ctyun-dashboard controlPower 开机/唤醒双重信令链路 (Triple Link)
    action: poweron (开机=1), awake (唤醒=18), shutdown (关机=2), reboot (重启=3)
    """
    auth_info = get_auth_info()
    if not auth_info:
        print("[!] 未找到官方客户端本地凭证，请确保已登录！")
        return False
        
    act = action.lower()
    op_type = 1
    action_cn = "开机"
    
    if act in ["poweron", "start", "on"]:
        op_type = 1
        action_cn = "开机"
    elif act in ["awake", "wakeup", "resume"]:
        op_type = 18
        action_cn = "唤醒"
    elif act in ["shutdown", "poweroff", "off"]:
        op_type = 2
        action_cn = "关机"
    elif act in ["reboot", "restart"]:
        op_type = 3
        action_cn = "重启"
        
    print(f"[*] 正在向天翼云下达电源控制指令: {action_cn} (operationType: {op_type}, 设备ID: {desktop_id})...")
    
    # 开机与唤醒专属的双重信令重试
    if op_type in [1, 18]:
        # 1. 尝试主信令 (1 或 18)
        res1 = send_operate(desktop_id, op_type, auth_info)
        if res1.get("code") == 0:
            print(f"[OK] ✅ 云电脑【{action_cn}】指令已成功生效！官方已确认启动。")
            return True
            
        last_msg = res1.get("msg", "")
        # 2. 互补信令 (1 ↔ 18)
        alt_op = 18 if op_type == 1 else 1
        alt_cn = "唤醒" if alt_op == 18 else "开机"
        res2 = send_operate(desktop_id, alt_op, auth_info)
        if res2.get("code") == 0:
            print(f"[OK] ✅ 云电脑【{alt_cn}】互补指令已成功生效！官方已确认启动。")
            return True
            
        # 3. 如果机房返回已处于运行状态
        if any(k in str(res1) or k in str(res2) for k in ["运行中", "已经开机", "正在进行"]):
            print(f"[OK] 云电脑已处于开机/运行状态中，无需重复开机。")
            return True
            
        print(f"[!] 开机指令未通过: {res1.get('msg')} / {res2.get('msg')}")
        return False
    else:
        res = send_operate(desktop_id, op_type, auth_info)
        if res.get("code") == 0:
            print(f"[OK] ✅ 云电脑【{action_cn}】指令已成功生效！")
            return True
        else:
            print(f"[!] {action_cn} 指令失败: {res.get('msg')}")
            return False

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("用法: python3 power.py <云电脑ID> [动作: poweron|awake|shutdown|reboot]")
        sys.exit(1)
    did = sys.argv[1]
    action = sys.argv[2] if len(sys.argv) > 2 else "poweron"
    control_power(did, action)

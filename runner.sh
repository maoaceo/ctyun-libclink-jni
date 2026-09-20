#!/bin/bash
# ==========================================================
# 天翼云官方客户端多实例与防冲突隔离管理快捷脚本
# ==========================================================

PYTHON_BIN="/usr/bin/python3"
MGR_SCRIPT="/root/ctyun-headless/instance_manager.py"

case "$1" in
    list)
        $PYTHON_BIN $MGR_SCRIPT list
        ;;
    start)
        # 用法: ./runner.sh start <实例名称> [机器备注/编码] [云电脑ID]
        $PYTHON_BIN $MGR_SCRIPT start "$2" "$3" "$4"
        ;;
    qr)
        # 用法: ./runner.sh qr <实例名称>
        $PYTHON_BIN $MGR_SCRIPT qr "$2"
        ;;
    stop)
        # 用法: ./runner.sh stop <实例名称>
        $PYTHON_BIN $MGR_SCRIPT stop "$2"
        ;;
    stop-all)
        $PYTHON_BIN $MGR_SCRIPT stop-all
        ;;
    *)
        echo "=========================================================="
        echo "天翼云电脑 多实例与设备隔离防冲突管理器"
        echo "=========================================================="
        echo "常用命令:"
        echo "  $0 list                                          # 列出所有实例及当前连接锁定的机器"
        echo "  $0 start <实例名> [机器备注/设备编码] [云电脑ID]   # 启动新实例 (自带防重复锁定)"
        echo "  $0 qr <实例名>                                   # 获取该实例的专属登录二维码"
        echo "  $0 stop <实例名>                                 # 停止指定实例"
        echo "  $0 stop-all                                      # 停止所有实例"
        echo "=========================================================="
        exit 1
        ;;
esac

#!/bin/bash

# Define variables
snmp_path=/etc/snmp
snmp_conf=${snmp_path}/snmp.conf
snmpd_conf=${snmp_path}/snmpd.conf
p910nd_conf=/etc/default/p910nd
iptables_conf=/etc/iptables/rules.v4

current_path=$(dirname "$0")
mib_file=${current_path}/CLINK-MIB.txt 
std_snmpd_conf=${current_path}/snmpd.conf

data_path=""
log_file=""

format_date=$(date +'%Y-%m-%d %H:%M:%S')
pre_install_check=0
config_snmp=0


#param1: command name
#param2: package name
#param3: bad exit value
function check_pkg_install {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking package ${1}..." >> ${log_file}
    keyword=${1}/
    if apt list --installed | grep -q "${keyword}"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Package ${1} exist." >> ${log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Package ${1} not found." >> ${log_file}

        if [ "${pre_install_check}" -eq 0 ]; then
            ### Update package list
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start updating package list..." >> ${log_file}
            apt update -y >> ${log_file}
            if [ $? -eq 0 ]; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Update success." >> ${log_file}
            else
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Update failed." >> ${log_file}
                if [ ! "${2}" = "-1" ]; then
                    exit ${2}
                fi
            fi
            
            ### systemd depends on libip4tc0 or libip4tc2 when installing p910nd/snmpd
            if apt list --installed | grep -q "libip4tc"; then
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Package libip4tcx exist." >> ${log_file}
            else
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Package libip4tcx not found." >> ${log_file}
                
                ### Try libip4tc0
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Start installing libip4tc0..." >> ${log_file}
                DEBIAN_FRONTEND=noninteractive apt install -y libip4tc0 >> ${log_file}
                if apt list --installed | grep -q "libip4tc0"; then
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Install success." >> ${log_file}
                else
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Install failed." >> ${log_file}
                    
                    ### Try libip4tc2
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Start installing libip4tc2..." >> ${log_file}
                    DEBIAN_FRONTEND=noninteractive apt install -y libip4tc2 >> ${log_file}
                     if apt list --installed | grep -q "libip4tc2"; then
                        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Install success." >> ${log_file}
                    else
                        echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Install failed." >> ${log_file}
                        exit ${2}
                    fi
                fi
            fi
            pre_install_check=1
        fi

        ## Install package
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start installing package ${1}..." >> ${log_file}
        DEBIAN_FRONTEND=noninteractive apt install -y ${1} >> ${log_file}
        if [ $? -eq 0 ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] ${1} installed." >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Install ${1} failed." >> ${log_file}
            if [ ! "${2}" = "-1" ]; then
                exit ${2}
            fi
        fi
    fi
}


#param1: service name
#param2: bad exit value 
function check_service_status {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking status of ${1}..." >> ${log_file}
    status=$(service ${1} status | grep "Active:" | sed -n 's/.*(\(.*\)).*/\1/p')
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${status}." >> ${log_file}
    if [ ! "${status}" = "running" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Bad status, start restarting service..." >> ${log_file}
        service ${1} restart
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Restart finished." >> ${log_file}
        status=$(service ${1} status | grep "Active:" | sed -n 's/.*(\(.*\)).*/\1/p')
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${status}." >> ${log_file}
        if [ "${status}" = "running" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Service ${1} is ready." >> ${log_file}
        else          
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Service ${1} is not functioning properly." >> ${log_file} 
            exit ${2}
        fi
    fi
}


#param1: service name
#param2: bad exit value 
function stop_service {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start stoping service ${1}..." >> ${log_file}
    if service ${1} status | grep -q "Active:"; then
        service ${1} stop
        status=$(service ${1} status | grep "Active:" | sed -n 's/.*(\(.*\)).*/\1/p')
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${status}." >> ${log_file}
        if [ "${status}" = "dead" || "${status}" = "failed" ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Stop ${1} success." >> ${log_file}
        else          
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Stop ${1} failed." >> ${log_file} 
            if [ ! "${2}" = "-1" ]; then
                exit ${2}
            fi
        fi
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Service not found" >> ${log_file}
    fi
}


function enable_autostart {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking auto-start status of ${1}..." >> ${log_file}
    query_cmd="systemctl is-enabled ${1}"
    res=$(${query_cmd})
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${res}" >> ${log_file}
    
    if ${query_cmd} | grep -q "enabled"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Already enabled." >> ${log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start enabling auto-start..." >> ${log_file}
        systemctl enable "$1"
        res=$(${query_cmd})
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${res}" >> ${log_file}
        if ${query_cmd} | grep -q "enabled"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Enable success" >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Enable failed" >> ${log_file}
            if [ ! "${2}" = "-1" ]; then
                exit ${2}
            fi
        fi
    fi
}


function disable_autostart {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking auto-start status of ${1}..." >> ${log_file}
    query_cmd="systemctl is-enabled ${1}"
    res=$(${query_cmd})
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${res}" >> ${log_file}
    
    if ${query_cmd} | grep -q "disabled"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Already disabled." >> ${log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start disabling auto-start..." >> ${log_file}
        systemctl disable "$1"
        res=$(${query_cmd})
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Status: ${res}" >> ${log_file}
        if ${query_cmd} | grep -q "disabled"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Disable success" >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Disable failed" >> ${log_file}
        fi
    fi
}


# param1: iptables chain
# param2: port that 9100 redirect to
# param3: bad exit value
function iptables_add_redir_rule {
    add_cmd=""
    if [ "${1}" = "PREROUTING" ]; then
        add_cmd="iptables -t nat -A PREROUTING -p tcp --dport 9100 -j REDIRECT --to-ports ${2}"
    elif [ "${1}" = "OUTPUT" ]; then
        add_cmd="iptables -t nat -A OUTPUT -p tcp -o lo --dport 9100 -j REDIRECT --to-ports ${2}"
    fi
    query_cmd="iptables -t nat -n -L ${1} --line"
    ${add_cmd}
    if ${query_cmd} | grep -q "9100"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Add ${1} redir rule success." >> ${log_file}
        redir_info=$(${query_cmd} | awk '/9100/ {print $8,$9,$11}')
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] New redir rule: ${redir_info}" >> ${log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Add failed." >> ${log_file}
        exit ${3}
    fi   
    if [ ! -e ${iptables_conf} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ${iptables_conf} not found." >> ${log_file}
    fi
    iptables-save > /etc/iptables/rules.v4  
}


#param1: iptables chain name
#param2: bad exit value
function iptables_delete_redir_rule {
    query_cmd="iptables -t nat -n -L ${1} --line"
    if ${query_cmd} | grep -q "9100"; then
        rule_id=$(${query_cmd} | awk '/9100/ {print $1}')
        redir_info=$(${query_cmd} | awk '/9100/ {print $8,$9,$11}')
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] ${1} rule found: ${redir_info}" >> ${log_file}
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start deleting rule..." >> ${log_file}
        iptables -t nat -D ${1} ${rule_id}
        if ${query_cmd} | grep -q "9100"; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Delete failed." >> ${log_file}
            if [ ! "${2}" = "-1" ]; then
                exit ${2}
            fi
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Delete success." >> ${log_file}
        fi
    else
         echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] No ${1} rules found." >> ${log_file}      
    fi
    if [ ! -e ${iptables_conf} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ${iptables_conf} not found." >> ${log_file}
    fi
    iptables-save > /etc/iptables/rules.v4
}


# Process parameters
vid=""
pid=""
device_id=""
switch="1"
while getopts "o:v:p:d:l:u:" opt; do
  case $opt in
    o)
      switch=$OPTARG
      ;;
    v)
      vid=$OPTARG
      ;;
    p)
      pid=$OPTARG
      ;;
    d)
      device_id=\"$OPTARG\"
      ;;
    l)
      log_file=$OPTARG
      ;;
    u)
      data_path=$OPTARG
      ;;
    \?)      
      exit 1
      ;;
  esac
done

# Check log file size
if [ -f ${log_file} ]; then
    file_size=$(stat -c%s "${log_file}")
    # echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Log file size: ${file_size} bytes" >> ${log_file}
    if [ ${file_size} -gt 1048576 ]; then          # If the size of log file is larger than 1MB, empty it
        rm ${log_file}
    fi
    echo "" >> ${log_file}
fi

# Display parameters
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] switch=${switch}" >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] vid=${vid}" >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] pid=${pid}" >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] device_id=${device_id}" >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] log_file=${log_file}" >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] data_path=${data_path}" >> ${log_file}


# Check root privileges
euid=$(id -u)
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Current euid is ${euid}" >> ${log_file}
if [ "${euid}" -eq 0 ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] The script has root privileges" >> ${log_file}
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] The script has no root privileges" >> ${log_file}
fi


# Make sure the root directory is mounted rw
if mount | grep "/ type" | grep -q "(rw"; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Root directory rw mount." >> ${log_file}
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Root directory ro mount." >> ${log_file}
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start remounting the root directory as rw." >> ${log_file}
    mount -o remount rw /
    if mount | grep "/ type" | grep -q "(rw"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Remounting success." >> ${log_file}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Remounting failed." >> ${log_file}
    fi
fi
            

# Clean
if [ "${switch}" = "0" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start stopping function..." >> ${log_file}
    
    ## Delete files
    if [ -d ${data_path} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start deleting data path..." >> ${log_file}
        rm -rf ${data_path}  # lpinfo_*
        if [ ! -d ${data_path} ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Delete success." >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Delete failed." >> ${log_file}
        fi
    fi
    
    ## Reset p910nd config
    sed -i "s/P910ND_NUM=.*/P910ND_NUM=\"\"/g" ${p910nd_conf}
    sed -i "s/^P910ND_OPTS=.*/P910ND_OPTS=\"\"/g" ${p910nd_conf}
    sed -i "s/P910ND_START=.*/P910ND_START=/g" ${p910nd_conf}
    
    ## Reset snmpd config
    sed -i "/clink/d" ${snmpd_conf}
    
    ## Remove custom mib
    sed -i '/mibs :/d' ${snmp_conf}
    
    ## Reset iptables config
    iptables_delete_redir_rule PREROUTING -1
    iptables_delete_redir_rule OUTPUT -1
    
    ## Stop service
    stop_service p910nd -1
    stop_service snmpd -1
    
    ## Disable auto-start
    disable_autostart p910nd
    disable_autostart snmpd
    
    exit 0
fi

if [ -z $vid ] || [ -z $pid ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Vid and pid not set." >> ${log_file}
    exit 1
fi

# Check if printer connected
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking if printer connected..." >> ${log_file}
lp=""
printer_connected=0
timeout=5
interval=1
elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
    for lp in /dev/usb/lp*
        do
            if test -c $lp; then
                printer_connected=1
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Printer connected." >> ${log_file}
                break       
            fi
    done
    if [ "${printer_connected}" -eq 1 ]; then
        break
    fi
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARN] Wating for printer connecting..." >> ${log_file}
    sleep ${interval}
    elapsed=$((elapsed + interval))
done
if [ "${printer_connected}" -eq 0 ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] No printer connected" >> ${log_file}
    exit 2
fi


# Match vid and pid
printer_matched=0
check_pkg_install udev 4
for lp in /dev/usb/lp*
    do
        if test -c $lp; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Detected $lp." >> ${log_file}
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start matching 0x${vid}:0x${pid}..." >> ${log_file}                
                cmd="udevadm info --attribute-walk --name ${lp}"
                if ${cmd} | grep -q "$vid" && ${cmd} | grep -q "$pid"; then
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Match success." >> ${log_file}
                    printer_matched=1
                    break
                else
                    echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Match failed." >> ${log_file}
                fi          
        fi
done
if [ "$printer_matched" -eq 0 ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] Target printer not found." >> ${log_file}
    exit 2
fi
lp_num=${lp#/dev/usb/lp}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Current lp number: ${lp_num}." >> ${log_file}


# Check if printer configured before
lpinfo_file=${data_path}/lpinfo_${vid}_${pid}
if [ ! -f ${lpinfo_file} ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] The printer is being first configured." >> ${log_file}
    config_snmp=1
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] The printer was configured before." >> ${log_file}
    
    ## Check if lp changed
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Reading last lp number from ${lpinfo_file}..." >> ${log_file}
    last_lp_num=-1
    read last_lp_num < "${lpinfo_file}"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Last lp number: ${last_lp_num}." >> ${log_file}
    if [ "${lp_num}" = "${last_lp_num}" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] lp not change, no need to reconfigure." >> ${log_file}
        
        ## Check p910nd and snmpd running status
        check_service_status snmpd 12
        check_service_status p910nd 13
        
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] All finished." >> ${log_file}
        exit 0
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] lp changed, need to reconfigure." >> ${log_file}
    fi
fi


# Check if packages installed
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking the packages necessary for configuration are installed..." >> ${log_file}
check_pkg_install p910nd 4
check_pkg_install snmpd 4
check_pkg_install snmp 4
check_pkg_install iptables 4
check_pkg_install iptables-persistent 4
check_pkg_install net-tools 4


# Configure p910nd
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start configuring p910nd..." >> ${log_file}
if [ ! -f ${p910nd_conf} ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][ERROR] ${p910nd_conf} not found." >> ${log_file}
    exit 5
fi
sed -i "s/P910ND_NUM=.*/P910ND_NUM=\"${lp_num}\"/g" ${p910nd_conf}
sed -i "s/^P910ND_OPTS=.*/P910ND_OPTS=\"-f \/dev\/usb\/lp${lp_num}\"/g" ${p910nd_conf}
sed -i "s/P910ND_START=.*/P910ND_START=1/g" ${p910nd_conf}
sync
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] p910nd configured." >> ${log_file}
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start restarting p910nd..." >> ${log_file}
service p910nd restart
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Restart finished.." >> ${log_file}
## Wait for p910nd to start listening
port=0
timeout=20
interval=1
elapsed=0
listen_success=0
while [ "$elapsed" -lt "$timeout" ]; do
    port=$(netstat -anp | grep p910 | awk '{print $4}' | sed 's/.*://')
    if echo "$port" | grep -q "910${lp_num}"; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Port ${port} is being listened on." >> ${log_file}
        listen_success=1
        break
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Port=${port}, listened failed" >> ${log_file}
    fi
    sleep ${interval}
    elapsed=$((elapsed + interval))
done
if [ "${listen_success}" -eq 0 ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Waiting for port listening timeout" >> ${log_file}
    exit 5
fi
## Set auto start
enable_autostart p910nd 5

# Check tcp port redirection rule
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking tcp port redirection rule..." >> ${log_file} 
iptables_prerouting_query_cmd="iptables -t nat -n -L PREROUTING --line"
## Delete old redir rule
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start deleting old rules..." >> ${log_file}
iptables_delete_redir_rule PREROUTING 6
iptables_delete_redir_rule OUTPUT 6
## Add new redir rule    
if [ ! "${port}" = "9100" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start adding new rules..." >> ${log_file}
    iptables_add_redir_rule PREROUTING ${port} 6       # Redir inbound traffic
    iptables_add_redir_rule OUTPUT ${port} 6           # Redir loopback traffic
fi


if [ "$config_snmp" -eq 1 ]; then
    # Get ieee1284_id if not set by parameters
    if [ -z "$device_id" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start extracting ieee1284_id using udevadm..." >> ${log_file}
        cmd="udevadm info --attribute-walk --name ${lp}"
        if ${cmd} | grep -q "ieee1284_id"; then
            device_id=$(${cmd} | grep "ieee1284_id" | awk -F'==' '{print $2; exit}')
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Get: ${device_id}." >> ${log_file}
        else 
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ieee1284_id not found." >> ${log_file}
        fi
    fi


    # Set custom mib
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start adding custom mib CLINK-MIB.txt..." >> ${log_file}
    if [ -f ${snmp_conf} ]; then
        sed -i '/mibs :/d' ${snmp_conf}
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ${snmp_conf} not found." >> ${log_file}
    fi
    echo "mibs :${mib_file}" >> ${snmp_conf}
    sync
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Custom mib CLINK-MIB.txt added." >> ${log_file}


    # Update snmpd subagent script
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start updating snmpd subagent script..." >> ${log_file}
    script_name=clinksnmpdsubagent.sh
    if [ ! -e ${snmp_path} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Path ${snmp_path} not found " >> ${log_file}
    fi
    script_file=${snmp_path}/${script_name}
    if [ -f ${script_file} ]; then
        > ${script_file}
    fi
    echo "#!/bin/bash" >> ${script_file}
    echo 'echo $2' >> ${script_file}
    echo "echo string" >> ${script_file}
    echo "echo ${device_id}" >> ${script_file}
    sync
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Snmpd subagent script updated." >> ${log_file}


    # Check snmpd.conf
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start checking snmpd config file..." >> ${log_file}
    replace_snmpd_conf=0
    if [ -e ${snmpd_conf} ]; then
        if grep -q "CLINK.conf" ${snmpd_conf} ; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] snmpd.conf is standard." >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] snmpd.conf is native." >> ${log_file}
            replace_snmpd_conf=1
        fi
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] ${snmpd_conf} not exists." >> ${log_file}
        replace_snmpd_conf=1
    fi
    if [ "${replace_snmpd_conf}" = "1" ]; then	
	if [ ! -e ${snmpd_conf}.bk ]; then
	    cp ${snmpd_conf} ${snmpd_conf}.bk 	
	    if [ -e ${snmpd_conf}.bk ]; then
		echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Backup original snmpd.conf success." >> ${log_file}
	    else
		echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Backup original snmpd.conf failed." >> ${log_file}
	    fi
	else
	    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Original snmpd.conf was backuped before." >> ${log_file}
	fi	        
        
        if [ -e ${std_snmpd_conf} ]; then
	    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start replacing snmpd.conf..." >> ${log_file}
	    cp -f ${std_snmpd_conf} ${snmp_path}
	    if grep -q "CLINK.conf" ${snmpd_conf} ; then
            	echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Replace snmpd.conf success." >> ${log_file}
            else
                echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Replace snmpd.conf failed." >> ${log_file}                
            fi	
	else
	    echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ${std_snmpd_conf} not exist." >> ${log_file}
        fi
    fi

    
    # Configure snmpd
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start configuring snmpd..." >> ${log_file}
    if [ ! -f ${snmpd_conf} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] ${snmpd_conf} not found." >> ${log_file}
    fi
    ## visible range 
    sed -i '/127.0.0.1:161/ {/^#/! s/^/#/}' ${snmpd_conf}                            # comment
    sed -i '/udp:161/s/^#//' ${snmpd_conf}                                           # uncomment
    ## community name
    sed -i '/default.*systemonly/d' ${snmpd_conf}                                    # delete
    sed -i '/rocommunity/{/public/{/localhost/{s/^#//}}}' ${snmpd_conf}              # uncomment
    sed -i '/rocommunity.*public.*localhost/ s/localhost/default/' ${snmpd_conf}     # modify
    ## set subagent script
    sed -i "/clinksnmp/d" ${snmpd_conf}
    echo "pass .1.3.6.1.4.1.2699 /bin/sh ${script_file}" >> ${snmpd_conf}
    sync
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Snmpd configured." >> ${log_file}
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start restarting snmpd..." >> ${log_file}
    service snmpd restart
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Sleep start" >> ${log_file}
    sleep 5
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Sleep end" >> ${log_file}
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Restart finished." >> ${log_file}
    check_service_status snmpd 7

    # Test snmpd subagent
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start testing snmpd subagent..." >> ${log_file}
    response=$(snmpget -v 1 -c public localhost .1.3.6.1.4.1.2699.1.2.1.2.1.1.3.1)
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Get response: ${response}." >> ${log_file}
    enable_autostart snmpd 7
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] No need to configure snmp." >> ${log_file}
fi


# Creat lpinfo file
echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Start recording lp info..." >> ${log_file}
 if [ ! -e ${data_path} ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Data path isn't exist, start creating..." >> ${log_file}
        mkdir -p ${data_path}
        if [ -e ${data_path} ]; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Create success." >> ${log_file}
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Create failed." >> ${log_file}
        fi
    fi
find "$data_path" -type f -name "lpinfo*" -delete
lpinfo_file=${data_path}/lpinfo_${vid}_${pid}
> ${lpinfo_file}
echo ${lp_num} >> ${lpinfo_file}
if [ ! -f ${flag_file} ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][WARNING] Record failed." >> ${log_file}
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] Record success, lp num ${lp_num} saved to ${lpinfo_file}" >> ${log_file} 
fi


echo "[$(date +'%Y-%m-%d %H:%M:%S')][INFO] All finished." >> ${log_file}
exit 0

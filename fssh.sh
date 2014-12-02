#!/bin/bash
####闪速批量并行远程执行命令脚本，120台机器的执行时间是10s内完成,开启闪速ssh优化选项后，120台机器可在2-3s内完成
####by laijingli2006@gmail.com
####2014/11/27

####指定远程主机列表或主机列表文件
list1="
192.168.100.139
192.168.100.164
192.168.100.165
192.168.100.216
"
list2=$(cat /root/vps_ip_list.txt)

list=$list1

####指定待执行的命令(适用不包含变量、特殊字符的普通命令，多个命令以;分割)或命令列表文件(适合所有命令，一条命令一行或多条命令一行以;分割)
cmd="date;ifconfig eth0"
#cmd="date;echo $HOSTNAME"
#cmd="date;ifconfig;sleep \$((\$RANDOM%5+1))"

####指定命令列表文件绝对路径，run locall script remotely:全局特殊字符转义到远程主机shell环境，通过将命令写入到文件，这样就可以避免单引号、双引号、特殊字符转义、远程变量等一系列复杂问题，兼容单独命令
#cmd=/root/210remote_cmd.txt

####在用户命令前执行uname，利用其记录到log中的关键字Linux判断任务是否执行成功
cmd="uname;$cmd"
#echo $cmd


####指定ssh相关参数
#remote_ssh_user=lai
remote_ssh_user=root
#remote_ssh_user_pass="654321"
remote_ssh_user_pass="vps_pass"
####普通ssh选项，相同任务每次执行时间基本相同
#ssh_options=" -o StrictHostKeyChecking=no"
####闪速ssh优化选项，采用ssh长连接复用技术,相同任务在10分钟内，第二次及以后执行时间在3s内
ssh_options=" -T -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -o ConnectTimeout=5  -o ControlMaster=auto -o ControlPath=/tmp/.ssh_mux_%h_%p_%r -o ControlPersist=600s "
####闪速ssh优化选项，在低速网络链接环境使用，采用ssh长连接复用技术,相同任务在10分钟内，第二次及以后执行时间在3s内
#ssh_options=" -C -tt -q -o StrictHostKeyChecking=no -o PubkeyAuthentication=no -o ConnectTimeout=5  -o ControlMaster=auto -o ControlPath=/tmp/.ssh_mux_%h_%p_%r -o ControlPersist=600s"
ssh_cmd="/usr/bin/sshpass -p${remote_ssh_user_pass} /usr/bin/ssh ${ssh_options}"


####初始化pid、ips数组及远程主机计数器num
pids=()
pid_exist_value=()
ips=()
num=0
####循环主机列表执行
for ip in $list ;do
  echo > /tmp/$ip.log
  #echo $ip:$cmd | tee -a /tmp/$ip.log
  echo $ip:$cmd >> /tmp/$ip.log
  ####后台运行ssh远程命令
  ${ssh_cmd} ${remote_ssh_user}@$ip bash -c $cmd >> /tmp/$ip.log 2>&1 & 
  ####此选项为待执行的命令为文件列表时开启
  #${ssh_cmd} ${remote_ssh_user}@$ip bash < $cmd >> /tmp/$ip.log 2>&1 &
  #echo $! >>/tmp/pid.txt
  pids[$num]=$!
  ####等待获取后台进程的退出状态值
  #wait ${pids[$num]} > /tmp/status_$ip.log &
  ####初始化pid_exist_value数组
  pid_exist_value[$num]=255
  ips[$num]=$ip
  #echo ${pids[$num]}----${ips[$num]}----${pid_exist_value[$num]} | tee -a /tmp/pids.txt
  num=$(($num+1))
  # echo num00000=$num
done

#exit

echo ============results report:================
#sleep 2

#echo pids=${pids[*]}
#echo  ips=${ips[*]}
pids_length=${#pids[@]}
echo pids_length:${pids_length}

echo
echo execute reslut check loop begin:


####循环检查pids数组中的pid是否运行结束的函数
array_check () {
  for i in `seq 0 $((${#pids[@]} - 1))` ;do
    #echo -------------------------------------array for loop----------------------
    #echo i=$i
    #echo pids[$i]=${pids[$i]}---${ips[$i]}
    if [  ${pids[$i]} == 0 ] ;then
       echo NULL >/dev/null
    else 
       ####通过/proc目录动态检查pid是否结束,执行成功说明进程还没有结束
       ls /proc | grep  ^${pids[$i]}$ 2>&1 >/dev/null
       pidstatus=$?
       #echo pidstatus=$pidstatus
       ###if pids is not exists in /proc,that indecates the process is over,and display execute result,clean respective array elements
       if [ $pidstatus != 0 ] ;then
          ####进程结束后，打印执行结果log
          echo
          echo  "****************************** remote screen results for pids[${pids[$i]}]  ips[${ips[$i]}] ********************************"
          #echo  pids[${pids[$i]}] remote ssh ips[${ips[$i]}] is over
          sed -n '1,3p' /tmp/${ips[$i]}.log|cut -d" " -f1|grep Linux >/dev/null 2>&1
          cmd_excute_status=$?
          if [  ${cmd_excute_status} == 0 ] ;then
             #echo cmd_excute_status:${cmd_excute_status}
             ####绿色闪烁
             echo -e "\033[32m\033[05m 执行成功\033[0m"
             echo -e "\033[32m\033[05m $(cat /tmp/${ips[$i]}.log)\033[0m"
             pid_exist_value[$i]=0
             complete_num_success=$((${complete_num_success}+1))
             #echo complete_num_success_tasks:[${complete_num_success}]
             #echo ${ips[$i]} >>/root/vps_authed.txt
          else
             echo -e "\033[31m\033[05m执行失败\033[0m"
             echo -e "\033[31m\033[05m $(cat /tmp/${ips[$i]}.log)\033[0m"
             #pid_exist_value[$i]=-1
             #echo ${ips[$i]} >>/root/vps_not_authed.txt
        fi
          #cat /tmp/${ips[$i]}.log
          #####同时pids数组中对应pid重置为0
          pids[$i]=0
          ips[$i]=0
          #echo ${pids[*]}
          ####进程结束，返回200供后续判断
          return 200
          break
       fi
    fi
    ###wait for 1 seconds to check whether the pids is over
    #sleep 3
 done
}


complete_num=0
#echo complete_num:${complete_num}
#echo  pids_length:${pids_length}
####如果完成任务数complete_num不等于pids数组长度，则循环直到所有任务结束
while [ ${complete_num} != ${pids_length} ] ;do
#echo =================================while loop=======================================
for ((j=0;j<${pids_length};j++)) ;do
   #echo ++++++++++++++++++++++++++++++ for  loop in while ++++++++++++++++++++++++++++
   #echo complete_num:${complete_num}
   #echo  pids_length:${pids_length}
   #echo j:$j
   array_check 
   ####根据array_check函数返回值是否成功来确定complete_num数的增加
   if [ $? == 200 ] ;then
      complete_num=$((${complete_num}+1))
      ####打印最近任务完成的数量
      echo -e "\033[35m\033[05mReport: complete_success_tasks/complete_tasks/total_tasks:[${complete_num_success}/${complete_num}/${pids_length}]\033[0m"
      #echo ========================================================================
   fi
   #sleep 1
done
done

echo
echo Good luck,all tasks has complete!



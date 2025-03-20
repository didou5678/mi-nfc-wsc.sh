#!/bin/sh

<<!
 **********************************************************
 * Author        : dido
 * Email         :  
 * Last modified : 2025-3-18
 * Filename      : mi-nfc-wsc.sh 
 * Description   : 设备 xiaomi ax3000t 自带一个i2c nfc芯片   使用ash shell 脚本 构造ndef wsc数据  刷入 i2c nfc设备  
                           实现 手机扫一下nfc 自动连接wifi 





 * *******************************************************
!


usage() {
cat << EOT
构造 nfc vnd.wfa.wsc  ,实现 手机扫一下nfc wifi自动连接 
只考虑一个payload的情况
这个脚本依赖软件 i2ctransfer,coreutils-od,coreutils-sleep
重复调用该脚本只会覆盖原有的ndef数据 不会追加数据 

-I 指定nfc i2cbus地址 使用 i2cdetect -l 获取 i2c-X  默认值 0
-C 指定chipaddress    使用 i2cdetect -y 0获取 默认值 0x57
-b 执行写入操作前 备份当前nfc tag数据到文件 如果没有指定则不会执行备份
-s 指定 ssid 字符
-p 指定wifi 密码
-a 认证方式 0001 Open; 0002 WPA; 0004 shared; 0008 wpa-eap ; 0010 wpa2-eap; 0020 wpa2
-e 加密方式 可选值 0001 None ; 0002 WEP; 0004 TKIP; 0008 AES; 000c MIXED
-h 显示help


调用示例
 sh mi-nfc-wsc.sh -I 0 -C 0x57 -s MyNfcTest -p  pass+W0rd -a 0040 -e 000c -b /tmp/nfc.bak

sh mi-nfc-wsc.sh -s hahaha-ssid -p  a12345678

EOT
return 0
}


#检测
if [ $(opkg list-installed|grep -c "i2c-tools") -ne 1 ]; then
echo "i2ctransfer no found,via 'opkg install i2c-tools' then retry" 
exit
fi

if [ $(opkg list-installed|grep -c "coreutils-od") -ne 1 ]; then
echo "od no found,via 'opkg install coreutils-od' then retry" 
exit
fi

if [ $(opkg list-installed|grep -c "coreutils-sleep") -ne 1 ]; then
echo "/usr/libexec/sleep-coreutils no found,via 'opkg install coreutils-sleep' then retry" 
exit 
fi


if [ $(i2cdetect -l|wc -l) -lt 1 ]; then
echo "i2c device no found"
exit
fi



#xiaomi ax3000t 显示 i2c-0  
#通过 i2cdetect -y 0 可以得到在 0x57
#使用 i2ctransfer -y 0 w2@0x57 0x0 0x0 r256  获取nfc储存的数据
#NKGBDSY

#i2ctransfer  不能执行太快 否则会写入失败  


#默认值
varBUSADDR=0
varCHIPADDR=0x57
varBAKFILE=
varSSID="mi-nfc-wsc-ssid"
varPSW="Pass-w0rd"
varAUTH="0020"
varENC="0008"



while getopts ':I:C:b:s:p:a:e:h' OPT; do
case $OPT in
	I)
	varBUSADDR=$OPTARG
	;;
	C)
	varCHIPADDR=$OPTARG
	;;
	b)
	varBAKFILE=$OPTARG
	;;
	s)
	varSSID=$OPTARG
	;;
	p)
	varPSW=$OPTARG
	;;
	a)
	varAUTH=$OPTARG
	;;
	e)
	varENC=$OPTARG
	;;
	h)
	usage
	exit
	;;
	\?)
	echo "Invalid option: -$OPTARG"
	exit 1
	;;
esac
done
shift $(($OPTIND - 1))

########################################################
#detect


i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0 r1
if [ $? -ne 0 ]; then
echo "i2c device i2cbus at: ${varBUSADDR} chip at: ${varCHIPADDR}   no found"
exit
fi
########################################################


VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0 r8)
VAR=$(echo $VAR|sed 's/0x//g'|sed 's/[ ]/:/g')
echo "nfc tag id: $VAR"


#BCC
# ct=0x88
v=136
BCC=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0 r4)
/usr/libexec/sleep-coreutils 0.1


for d in  $(echo $BCC); do
t=$(printf %d $d)
v=$((v ^ t))
done

if [ $v -eq 0 ]; then
echo "CT1 check ok"
else
echo "CT1 check fault"
fi

 
BCC=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x4 r5)
/usr/libexec/sleep-coreutils 0.1

v=0
for d in  $(echo $BCC); do
t=$(printf %d $d)
v=$((v ^ t))
done

if [ $v -eq 0 ]; then
echo "CT2 check ok"
else
echo "CT2 check fault"
fi

#internal
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x9  r1)
echo "internal: $VAR"

#Static lock
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0a r2)
echo "nfc static locl: $VAR"

#CC
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0c  r1)
echo "cc function cluster code: $VAR"
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0d  r1)
echo "cc nfc tag version: $VAR"
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0e  r1)
VAR=$(printf %d $VAR)
ndefmaxsize=$((VAR * 8))
echo "cc ndef max size in byte: $ndefmaxsize"
VAR=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x0 0x0f  r1)
echo "cc nfc tag access capability: $VAR"



#tag大小的偏移量
OFS_NDEFSIZE=0x11

ndefcursize=$(i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x00 $OFS_NDEFSIZE r1)
ndefcursize=$(printf %d $ndefcursize)
echo "ndef current size in byte $ndefcursize"


########################################################
# backup nfc data

##备份整个nfc tag
#if [ -n "${varBAKFILE}" ]; then
#ndefmaxsize=$((ndefmaxsize+ $OFS_NDEFSIZE +1))
#i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x00 0x00 r${ndefmaxsize} > ${varBAKFILE}
#fi



#仅备份 有效数据的nfc size  包含 nfc头+ndef
if [ -n "${varBAKFILE}" ]; then
ndefcursize=$((ndefcursize + $OFS_NDEFSIZE +1))
i2ctransfer -y ${varBUSADDR} w2@${varCHIPADDR} 0x00 0x00 r${ndefcursize} > ${varBAKFILE}
fi


########################################################
#build ndef header type   application/vnd.wfa.wsc 
#只考虑一个payload 

# 0xd2 == 11010010  mb=1 me=1 cf=0 sr=1 il=0 tnf=2

NDEFHDR="0xd2 0x17"
NDEFPLL="0x00" #payloadlen占位填充0x00 


#NDEFTYPE=$(echo -n "application/vnd.wfa.wsc"|xxd -i -c 30|sed 's/,//g')
#NDEFTYPELEN=$(echo -n ${NDEFTYPE}|awk '{print NF}')  == 0x17 

NDEFTYPE="0x61 0x70 0x70 0x6c 0x69 0x63 0x61 0x74 0x69 0x6f 0x6e 0x2f 0x76 0x6e 0x64 0x2e 0x77 0x66 0x61 0x2e 0x77 0x73 0x63"
#没有idlen和id



########################################################
#build ndef payload 

#100e
HDR100E="0x10 0x0e"
HDR100ELEN="0x00 0x00" #---长度待定
#按照 构造 基础长度为35 再+ssidlen+pswlen 
hdrlen=35
HDR1026="0x10 0x26 0x00 0x01 0x01"

#ssid 1045
HDR1045="0x10 0x45"
#HDR1045DATA=$(echo -n "${varSSID}"|xxd -c 30 -i |sed 's/,//g') ------------------------------------------------------------

HDR1045DATA=$(echo -n "${varSSID}" | od -An -t x1|awk '{for(i=1;i<=NF;i++) {printf "0x%s " ,$i}}')
ssidlen=$(echo -n ${HDR1045DATA}|awk '{print NF}')
HDR1045LEN=$(printf  "0x%02x" ${ssidlen}) #ssid长度不会超过0xff 因此下面填充00
HDR1045LEN="0x00 $HDR1045LEN"

#echo -n "$HDR1045DATA"|awk -F " " '{for(i=1;i<=NF;i++) {print $i}}'
#不要采用这个方法  先写到文件 再从文件逐个读取再写入i2c
#i2c_writebyte 0x39 $HDR1045DATA
#echo  $HDR1045 $HDR1045LEN $HDR1045DATA 

#auth 1003
HDR1003="0x10 0x03 0x00 0x02"
H16=$(echo $varAUTH |cut -c 1-2)
H16=0x$H16
L16=$(echo $varAUTH |cut -c 3-4)
L16=0x$L16
HDRAUTH="$H16 $L16"
#echo $HDRAUTH
#echo  "$HDR1003 $HDRAUTH"

#encrypt 100f
HDR100F="0x10 0x0f 0x00 0x02"
H16=$(echo $varENC |cut -c 1-2)
H16=0x$H16
L16=$(echo $varENC |cut -c 3-4)
L16=0x$L16
HDRENC="$H16 $L16"
#echo  "$HDR100F $HDRENC"

#wifi psk 1027
HDR1027="0x10 0x27"
#HDR1027DATA=$(echo -n "${varPSW}"|xxd -c 30 -i|sed 's/,//g')  ---------------------------------------------------
HDR1027DATA=$(echo -n "${varPSW}" | od -An -t x1|awk '{for(i=1;i<=NF;i++) {printf "0x%s " ,$i}}')
pswlen=$(echo -n ${HDR1027DATA}|awk '{print NF}')
HDR1027LEN=$(printf  "0x%02x" ${pswlen}) #长度不会超过0xff 下面填充00
HDR1027LEN="0x00 $HDR1027LEN"
#echo  $HDR1027 $HDR1027LEN $HDR1027DATA

#mac地址 1020
HDR1020="0x10 0x20 0x00 0x06 0xff 0xff 0xff 0xff 0xff 0xff"
hdrlen=$((hdrlen + $ssidlen + $pswlen))
#echo $hdrlen
#通常 payloadlen-4=100e len 
HDR100ELEN=$(printf  "0x%02x" $hdrlen)
HDR100ELEN="0x00 $HDR100ELEN"

PLDATA="$HDR100E $HDR100ELEN $HDR1026 $HDR1045 $HDR1045LEN $HDR1045DATA $HDR1003 $HDRAUTH $HDR100F $HDRENC $HDR1027 $HDR1027LEN $HDR1027DATA $HDR1020"
#echo $PLDATA

NDEFPLL=$(echo -n ${PLDATA}|awk '{print NF}')
NDEFPLL=$(printf  "0x%02x" $NDEFPLL)
#echo $NDEFPLL


##############################
#write bytes to nfc 


#1.   tag size  
#偏移 0x11 跳过 nfc tag 制造商描述部分 这部分可以被覆盖 直接ndef开头 
#tagsize= +  ndef头长度26byte   + payloadlen

TAGSIZE=26 
TAGSIZE=$((TAGSIZE + NDEFPLL))
TAGSIZE=$(printf  "0x%02x" $TAGSIZE)
#echo "tag size= $TAGSIZE"


i2ctransfer -y -v ${varBUSADDR} w3@${varCHIPADDR} 0x00 ${OFS_NDEFSIZE} $TAGSIZE 
#防止 写入太快 导致i2c 写入异常
/usr/libexec/sleep-coreutils 0.1

##############################

# 2.  NDEF HEADER
#修改payloadlen的值  这里只考虑 存在一个payload的情况 ---------------这里0x14

#i2ctransfer -y ${varBUSADDR} w3@${varCHIPADDR} 0x00 0x14 $NDEFPLL 

NDEFDATA="$NDEFHDR $NDEFPLL $NDEFTYPE"
OFS_HDR=$OFS_NDEFSIZE

for d in  $(echo $NDEFDATA); do

OFS_HDR=$(printf %d $OFS_HDR)
OFS_HDR=$((OFS_HDR + 1))
OFS_HDR=$(printf "0x%02x" $OFS_HDR)

#echo  "$OFS_HDR = $d "

i2ctransfer -y -v ${varBUSADDR} w3@${varCHIPADDR} 0x00 $OFS_HDR $d
/usr/libexec/sleep-coreutils 0.1
done

 

##############################

# 3. payload
#payload 写入偏移 0x2c  一个payload的情况
#OFS_PL=0x80  #测试位置

OFS_PL=$OFS_HDR
#echo "data:  $PLDATA"
#echo "offset: $OFS_PL"
#echo "length: $NDEFPLL"

for d in  $(echo $PLDATA); do

OFS_PL=$(printf %d $OFS_PL)
OFS_PL=$((OFS_PL + 1))
OFS_PL=$(printf "0x%02x" $OFS_PL)

#echo $OFS_PL=$d
i2ctransfer -y -v ${varBUSADDR} w3@${varCHIPADDR} 0x00 $OFS_PL $d

#清空为0x00
#i2ctransfer -v -y ${varBUSADDR} w3@${varCHIPADDR} 0x00 $OFS_PL 0x00 

#由于i2c 写入太快会无效  使命令执行暂停100ms
/usr/libexec/sleep-coreutils 0.1
done







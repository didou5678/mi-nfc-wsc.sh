# mi-nfc-wsc.sh
一个基于 openwrt ash 的 脚本,适用于小米 ax3000t路由器,用于向该设备自带的 nfc芯片 刷入 nfc ndef wsc 数据,以实现手机扫一下 ax3000t的nfc 然后自动连接wifi  

# 实现方法
## 安装软件 opkg install i2c-tools
### 执行  i2cdetect -l 

输出
i2c-0	i2c       	i2c-mt65xx                      	I2C adapter
得到 nfc 的 i2cbus 为 0 

执行 
i2cdetect -F 0
可获取 i2c的 Functionalities

执行
i2cdetect -y 0
执行结果 得到 chipaddr 在 0x57 

### 读取和写入
i2cget和i2cset 似乎并不能有效获取0x57的数据,所以这里使用  i2ctransfer

如 读取起始位置0x00 偏移0x11
i2ctransfer -y 0 w2@0x57 0x0 0x11 r1
执行结果得到一个 16进制 
0x55 
根据nfc 数据结构 偏移0x11 存储的值是 ndef数据的大小 

写入数据 偏移0x80的位置 写入 0xaa
i2ctransfer -y 0 w3@0x57 0x0 0x80  0xaa
w3需要设置为3字节才能有效写入 

另外 i2ctransfer无法同时写入 多个数据块 只能安装每个byte的方式 逐个写入
并且 每次写入i2c的间隔不能太快 否则会提示写入失败 所以这里额外安装了 coreutils-sleep
 因为 自带的sleep 最小以秒为单位 这样太费时间了
使用 /usr/libexec/sleep-coreutils 0.1s 将执行间隔控制在100ms , i2ctransfer 在for循环写入byte执行良好

# ndef的数据存储布局和提取
上面提及 偏移 0x11 为 ndef数据的长度 ,而  偏移 0x0e为 整个nfc tag的可存储的bytes 
根据i2ctransfer 得到16进制  * 8 就是存储大小

##  0xd2
偏移 0x12 
i2ctransfer -y 0 w2@0x57 0x00 0x12 r18

对应 二进制  11010010  mb=1 me=1 cf=0 sr=1 il=0 tnf=2
sr=1 只有一个payload 
il=1才有 id和idlen 否则没有该字段

## type length 
i2ctransfer -y 0 w2@0x57 0x00 0x13 r1
0x17   为 application/vnd.wfa.wsc  长度

## payloadlen 
i2ctransfer -y 0 w2@0x57 0x00 0x14 r1
为 payload长度,而payload就是 存储 wsc数据的部分


## type
长度为 type length 0x17
i2ctransfer -y 0 w2@0x57 0x00 0x15 r0x17
得到 0x61 0x70 0x70 0x6c 0x69 0x63 0x61 0x74 0x69 0x6f 0x6e 0x2f 0x76 0x6e 0x64 0x2e 0x77 0x66 0x61 0x2e 0x77 0x73 0x63
其实就是 application/vnd.wfa.wsc 转储 16进制数据
echo -n "application/vnd.wfa.wsc"|xxd -i -c 30|sed 's/,//g'

## payload
长度 有上面的 payloadlen决定

### 100e头
i2ctransfer -y 0 w2@0x57 0x00 0x2c r4
得到 0x10 0x0e 0x00 0x36 100e wifi头   0x36 为 整个 wifiheader 长度

### 1026头 
 网络 id  已废弃 占位使用
i2ctransfer -y 0 w2@0x57 0x00 0x30 r5
0x10 0x26 0x00 0x01 0x01 
1026后面带  网络字段ID对应的长度为0x0001 值为0x01

### 1045头
储存 ssid 
i2ctransfer -y 0 w2@0x57 0x00 0x35
0x10 0x45 0x00 0x0b
0x0b 为ssid的长度
获取ssid
i2ctransfer -y 0 w2@0x57 0x00 0x39 r0x0b
0x68 0x61 0x68 0x61 0x68 0x61 0x2d 0x73 0x73 0x69 0x64

转换为ascii字符
printf "\\x68" 得 h
printf "\\x61" 得 a
每个16进制诸如此类执行

### 1003头 
认证类型
i2ctransfer -y 0 w2@0x57 0x00 0x44 r4
得到 0x10 0x03 0x00 0x02
0x00 0x02 本字段长度 
 0x00 0x20  为 WPA2-Personal

### 100f 头
加密类型
i2ctransfer -y 0 w2@0x57 0x00 0x4a r6
0x10 0x0f 0x00 0x02 0x00 0x08
0x00 0x02 本字段长度 
0x00 0x08 AES

### 1027头
wifi密码
i2ctransfer -y 0 w2@0x57 0x00 0x50 r4
0x10 0x27 0x00 0x09 密码长度
i2ctransfer -y 0 w2@0x57 0x00 0x54  r9
0x61 0x31 0x32 0x33 0x34 0x35 0x36 0x37 0x38
逐个打印得到密码
printf "\\x61"

### 1020头   
mac地址
0x10 0x20 0x00 0x06 mac地址长度 6bytes
0x10 0x20 0x00 0x06 0xff 0xff 0xff 0xff 0xff 0xff


#构造ndef数据

由于 ash无法使用 数组 因此 脚本使用了大量的变量 几十个吧 
也不能像优雅的c语言一样 直接16进制运算 在shell环境每次需要将16进制转换10进制再运算,实际上可以使用bc命令

诸如此般
PLDATA="$HDR100E $HDR100ELEN $HDR1026 $HDR1045 $HDR1045LEN $HDR1045DATA $HDR1003 $HDRAUTH $HDR100F $HDRENC $HDR1027 $HDR1027LEN $HDR1027DATA $HDR1020"
将构造的数据 由一个变量保存
然后使用  
i2ctransfer -y -v ${varBUSADDR} w3@${varCHIPADDR} 0x00 ${OFS_NDEFSIZE} $TAGSIZE 
逐个写入 nfc芯片


# 执行脚本 mi-nfc-wsc.sh
openwrt 系统 
选项
-I 指定nfc i2cbus地址 使用 i2cdetect -l 获取 i2c-X  默认值 0
-C 指定chipaddress    使用 i2cdetect -y 0获取 默认值 0x57
-b 执行写入操作前 备份当前nfc tag数据到文件 如果没有指定则不会执行备份
-s 指定 ssid 字符
-p 指定wifi 密码
-a 认证方式 0001 Open; 0002 WPA; 0004 shared; 0008 wpa-eap ; 0010 wpa2-eap; 0020 wpa2
-e 加密方式 可选值 0001 None ; 0002 WEP; 0004 TKIP; 0008 AES; 000c MIXED
-h 显示help

执行 例子

sh mi-nfc-wsc.sh -I 0 -C 0x57 -s MyNfcTest -p  pass+W0rd -a 0020 -e 000c -b /tmp/nfc.bak

sh mi-nfc-wsc.sh -s hahaha-ssid -p a12345678














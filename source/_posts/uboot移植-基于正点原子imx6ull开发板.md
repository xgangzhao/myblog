---
title: uboot移植--基于正点原子imx6ull开发板
date: 2025-11-26 01:07:45
tags: [uboot]
---

## uboot版本
选择lf_v2024.04_6.6.52_2.2.x

## 参考nxp的imu6ullevk开发板，进行移植

通常我们要做的事情：  
修改设备树name，修改CONFIG_TARGET  
修改kconfig，添加target,see arch/arm/mach-imx/mx6/Kconfig  
添加板级头文件，并修改  
添加板级文件夹，并修改  
添加并修改设备树  

### defconfig
在uboot-imx/configs目录下，copy mx6ull_14x14_evk_emmc_defconfig 到 mx6ull_14x14_zxg_emmc_defconfig  

修改如下：
```c
CONFIG_ARM=y
CONFIG_ARCH_MX6=y
CONFIG_SYS_MALLOC_LEN=0x1000000
CONFIG_NR_DRAM_BANKS=1
CONFIG_SYS_MEMTEST_START=0x80000000
CONFIG_SYS_MEMTEST_END=0x88000000
CONFIG_ENV_SIZE=0x2000
CONFIG_ENV_OFFSET=0xE0000
CONFIG_MX6ULL=y
CONFIG_TARGET_MX6ULL_14X14_ZXG_EMMC=y
# CONFIG_LDO_BYPASS_CHECK is not set
CONFIG_SYS_I2C_MXC_I2C1=y
CONFIG_SYS_I2C_MXC_I2C2=y
CONFIG_DM_GPIO=y
CONFIG_DEFAULT_DEVICE_TREE="imx6ull-14x14-zxg-emmc"
CONFIG_SUPPORT_RAW_INITRD=y
CONFIG_USE_BOOTCOMMAND=y
```

### 板级文件修改
copy board/freescale/mx6ullevk 到 board/freescale/mx6ull_zxg_emmc  
修改makefile，使得mx6ull_zxg_emmc.c文件参与编译  
修正Kconfig  
修正该目录下所有路径名  
.c文件中的checkboard函数   

### 设备树修改
检查引脚，地址，参数等信息

#### 修复网络驱动
查看原理图可发现，phy引脚有冲突
移除其它模块对引脚 (gpio5 7, gpio5 8）的使用 
```bash
	spi-4 {
		compatible = "spi-gpio";
		pinctrl-names = "default";
		pinctrl-0 = <&pinctrl_spi4>;
		status = "okay";
		gpio-sck = <&gpio5 11 0>;
		gpio-mosi = <&gpio5 10 0>;
		 /* cs-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>; */
		num-chipselects = <1>;
		#address-cells = <1>;
		#size-cells = <0>;

		gpio_spi: gpio@0 {
			compatible = "fairchild,74hc595";
			gpio-controller;
			#gpio-cells = <2>;
			reg = <0>;
			registers-number = <1>;
			registers-default = /bits/ 8 <0x57>;
			spi-max-frequency = <100000>;
			/* enable-gpios = <&gpio5 8 GPIO_ACTIVE_LOW>; */
		};
	};
};
...
...
pinctrl_spi4: spi4grp {
		fsl,pins = <
			MX6UL_PAD_BOOT_MODE0__GPIO5_IO10	0x70a1
			MX6UL_PAD_BOOT_MODE1__GPIO5_IO11	0x70a1
			/* MX6UL_PAD_SNVS_TAMPER7__GPIO5_IO07	0x70a1 */
			/* MX6UL_PAD_SNVS_TAMPER8__GPIO5_IO08	0x80000000 */
		>;
	};
```

添加phy复位引脚：
```bash
&iomuxc {
	pinctrl_enet1rst: enet1rstgrp {
		fsl,pins = <
			MX6UL_PAD_SNVS_TAMPER7__GPIO5_IO07	0x10b0
		>;
	};

	pinctrl_enet2rst: enet2rstgrp {
		fsl,pins = <
			MX6UL_PAD_SNVS_TAMPER8__GPIO5_IO08	0x10b0
		>;
	};
};

&fec1 {
	pinctrl-0 = <&pinctrl_enet1 &pinctrl_enet1rst>;
	phy-reset-gpios = <&gpio5 7 GPIO_ACTIVE_LOW>;
    phy-reset-duration = <200>;
    phy-reset-post-delay = <200>;
};

&fec2 {
	pinctrl-0 = <&pinctrl_enet2 &pinctrl_enet2rst>;
	phy-reset-gpios = <&gpio5 8 GPIO_ACTIVE_LOW>;
    phy-reset-duration = <200>;
    phy-reset-post-delay = <200>;
};
```



### 修复LCD驱动
修改时序参数
```bash
display-timings {
			native-mode = <&timing0>;

			timing0: timing0 {
				clock-frequency = <51200000>;
				hactive = <800>;
				vactive = <480>;
				hfront-porch = <210>;
				hback-porch = <46>;
				hsync-len = <1>;
				vback-porch = <23>;
				vfront-porch = <22>;
				vsync-len = <1>;
				hsync-active = <0>;
				vsync-active = <0>;
				de-active = <1>;
				pixelclk-active = <0>;
			};
		};
```

### 构建
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- distclean
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- mx6ull_14x14_zxg_emmc_defconfig
make ARCH=arm CROSS_COMPILE=arm-none-linux-gnueabihf- -j16

### 烧录
sudo dd iflag=dsync oflag=dsync if=u-boot-dtb.imx of=/dev/sda bs=512 seek=2

### 设置uboot参数
```bash
eth1addr=b8:ae:1d:01:00:00
setenv ipaddr			开发板ip
setenv gatewayip		网关
setenv serverip			host ip
```

---

>下一步可以选择移植新版的linux kernel，主要需要做的事情就是为kernel修改dts，修复网络、LCD驱动等。为了方便调试，可以用tftp burn zImage和dtb，NFS挂载rootfs
```bash
setenv bootcmd "tftp 80800000 zImage; tftp 83000000 imx6ull-14x14-zxg-emmc.dtb;bootz 80800000 - 83000000"
setenv bootargs "console=ttymxc0,115200 root=/dev/nfs nfsroot=192.168.0.103:/home/zhaoxigang/linux/nfs/rootfs,vers=3,proto=tcp rw ip=192.168.0.110:192.168.0.103:192.168.0.1:255.255.255.0::eth0:off"
```

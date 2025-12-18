---
title: Linux设备驱动模型--主机驱动和外设驱动分离
date: 2025-12-19 00:40:15
tags: [Linux, device, driver]
---

主机驱动和外设驱动分离是一种核心的驱动架构设计思想，旨在解耦硬件控制器与具体设备，提高代码复用性和可移植性。这种设计广泛应用于SPI、I2C、USB等总线子系统中。
## 核心思想
分离的本质是将驱动拆分为两个独立部分： 
- 主机驱动（Host Driver）：负责操作SoC内部的控制器硬件，产生总线波形（如SPI时序、I2C起始/停止信号）
- 外设驱动（Peripheral Driver）：负责实现具体设备的功能逻辑（如触摸屏采样、网卡收发），通过标准API请求主机驱动完成总线传输。
两者通过核心层（Core Layer）作为中间纽带通信，核心层提供统一的传输接口和数据结构定义，屏蔽底层差异。
## 四个关键软件模块
该架构涉及明确分工的四个模块：
- 主机端驱动  
直接操作控制器寄存器（如SPI的波特率、模式配置）
实现transfer_one_message等底层传输函数  
示例：pl022_probe()中注册spi_controller，并填充setup和transfer_one_message回调
- 核心层（连接纽带）  
提供标准API（如spi_sync()、spi_async()）
定义通用数据结构（如spi_transfer、spi_message）
将外设请求路由到对应的主机驱动
- 外设端驱动  
在probe()中注册具体设备类型（如input_dev、net_device）
通过核心层API发起传输请求  
示例：spi_driver结构体与platform_driver高度相似，体现通用模板设计
- 板级逻辑  
描述硬件连接关系（谁接在哪个控制器、片选信号等）  
实现方式：  
传统：arch/arm/mach-xx板文件中定义spi_board_info数组    
现代：设备树（Device Tree）中配置compatible属性
---
title: GPIO 子系统与 Pinctrl 子系统的关系和理解
date: 2025-11-30 00:03:55
tags: [Linux, Driver]
---

在嵌入式 Linux 系统中，GPIO（General Purpose Input/Output）子系统和Pinctrl（Pin Control）子系统都是用于处理硬件引脚（GPIO pins）的重要模块，但它们的功能、职责和实现方式有所不同。

## GPIO 子系统
### 功能

GPIO 是一种通用的输入输出接口，允许操作硬件的数字信号引脚（例如 LED、按钮、传感器等）。这些引脚通常由硬件平台的处理器（SOC）提供。

GPIO 子系统 负责：

- 管理 GPIO 引脚的 配置、状态（输入/输出、低电平/高电平等）。

- 提供 API 接口，如 gpio_request、gpio_direction_output、gpio_set_value 等，供驱动程序或用户空间应用程序控制 GPIO 引脚的电平、方向等。

### 常用 API

gpio_request(): 申请一个 GPIO 引脚。

gpio_direction_output(): 设置 GPIO 为输出模式。

gpio_set_value(): 设置 GPIO 电平。

gpio_get_value(): 读取 GPIO 电平。

gpio_free(): 释放 GPIO 引脚。

### 工作原理

GPIO 控制 是基于硬件引脚的数字信号传输。在 Linux 中，GPIO 是通过访问 SOC 的引脚寄存器来进行控制的。开发者通过 GPIO 控制硬件，主要用于处理输入输出设备，如按钮、LED、继电器等。

## Pinctrl 子系统
### 功能

Pinctrl 子系统 主要用于管理和配置引脚的 多重功能（muxing）和 电气属性（电压、电流、上拉/下拉、驱动能力等）。

在一个处理器中，每个物理引脚（例如 GPIO1、GPIO2）可能有 多个功能（例如 UART、SPI、I2C、GPIO 等），Pinctrl 子系统负责选择和配置这些功能，并确保不同功能之间的协调。

### 常用 API

pinctrl_get(): 获取 pinctrl 配置。

pinmux_select(): 配置引脚的多重功能（如 UART、SPI、GPIO）。

pinctrl_select_default(): 配置引脚为默认状态（通常是 GPIO）。

### 工作原理

Pinctrl 子系统 配置引脚的功能选择和电气属性。例如，处理器的某些引脚在某些模式下可能是 UART 的 RX/TX 引脚，而在其他模式下可能是 GPIO 引脚。Pinctrl 子系统在不同模式间切换时，确保正确设置。

例如，某个引脚被配置为 GPIO 时，它会作为普通的输入/输出端口；而当被配置为 UART 时，它会变为 UART 接口的 RX 或 TX。

## GPIO 子系统与 Pinctrl 子系统的关系

虽然 GPIO 子系统 和 Pinctrl 子系统 处理的是同一类硬件资源（即引脚），但它们的作用和层次不同：

|功能 |	GPIO 子系统	| Pinctrl 子系统 |
|---|---|---|
|管理|	主要管理引脚的输入输出状态、方向和电平（高/低）|	管理引脚的多功能复用（muxing）和电气属性|
|层次	|GPIO 子系统是一个 更高层的接口，通过它可以控制硬件引脚的电平、方向|	Pinctrl 子系统是一个 底层配置，提供引脚功能的切换与电气配置|
|控制的内容|	GPIO 引脚的状态（例如控制 LED、按钮）|	GPIO 引脚的功能选择（例如切换为 UART、I2C 等）|
|调用方式|	通过 API 进行 GPIO 控制，如 gpio_request()、gpio_set_value()|	通过设备树和 pinctrl_* API 配置引脚功能和电气属性|


### 如何协调工作

- 硬件层面的映射：

每个物理引脚通常有多个功能，可以通过 Pinctrl 子系统 配置选择某个功能。

配置完成后，GPIO 子系统可以操作这个引脚。例如，可以在一个引脚上选择 UART 功能来发送数据，也可以选择 GPIO 功能来控制一个 LED。

- 设备树的定义：

在设备树中，Pinctrl 子系统 和 GPIO 子系统 都需要进行相应的配置。Pinctrl 负责配置引脚的多功能模式（例如，把引脚设置为 UART），而 GPIO 子系统负责后续对该引脚的操作（例如，读取按钮的状态或控制 LED）。

例如，设备树中的配置可能如下：

&gpio1 {
    pinctrl-names = "default";
    pinctrl-0 = <&gpio1_pins>;
    led-gpio = <&gpio1 3 GPIO_ACTIVE_LOW>; // 这里是GPIO控制
};


在这个例子中，pinctrl-0 配置了 GPIO1 引脚的功能（例如把它设置为 GPIO 功能），而 led-gpio 通过 GPIO 子系统来控制这个引脚的电平。

## 总结

GPIO 子系统 负责引脚的 输入输出控制，通过设置引脚电平、方向等来进行硬件控制。

Pinctrl 子系统 负责引脚的 多功能复用配置，使得同一引脚可以在不同的硬件功能之间切换。

### 二者的关系：

Pinctrl 子系统 主要进行硬件引脚功能的选择和配置（例如，设置为 UART、SPI 或 GPIO），

GPIO 子系统 通过操作引脚电平进行控制。

这两个子系统通常是配合使用的，通过设备树来协调硬件功能的配置，GPIO 子系统在硬件功能被选择后操作引脚。
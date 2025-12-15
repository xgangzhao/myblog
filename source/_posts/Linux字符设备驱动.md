---
title: Linux字符设备驱动
date: 2025-12-15 12:41:48
tags: [Linux, device, drivers]
---

>最近在系统地回顾 Linux 设备驱动基础，这一篇主要是字符设备驱动。一边看内核源码，一边把思路和常用 API 重新梳理了一遍，整理一下，方便以后自己翻

## 我理解的字符设备是什么

在 Linux 中，字符设备（Character Device）是一类按字节流进行访问的设备。它的典型特征是：  

    不经过 page cache  
    面向字节而不是块  
    用户态直接通过 open / read / write / ioctl 访问  

我在实际接触到的字符设备基本包括：  
GPIO  
I2C / SPI  
UART  
watchdog  
各种控制类外设  

内核里的访问路径大致如下：
```
用户态
 └─ open / read / write / ioctl
    └─ VFS
       └─ cdev（字符设备层）
          └─ 具体驱动
```

所以从实现角度看，一句话就能概括：

字符设备 = cdev + file_operations + 设备节点

## 整体编写流程（先有全局感）

我自己在写字符设备驱动时，基本都会沿着下面这条固定主线走： 

    申请设备号（dev_t）   
    初始化并注册 cdev
    创建 /dev 设备节点    
    实现 file_operations   
    处理并发、阻塞、唤醒等问题  
    模块卸载时释放资源  

字符设备的好处就在于：流程非常稳定，套路几乎不变。下面按步骤展开。

### 申请设备号（dev_t）

字符设备通过 主设备号 + 次设备号 来唯一标识。

#### 动态申请
```cpp
dev_t dev;
alloc_chrdev_region(&dev, 0, 1, "mychardev");
```

参数含义：  
dev：返回的设备号（包含 major/minor）  
0：起始 minor  
1：设备个数  

一般情况下，我都会用动态申请，避免和系统里已有的设备号冲突。

#### 卸载时释放
```cpp
unregister_chrdev_region(dev, 1);
```

### 初始化并注册 cdev

cdev 是字符设备在内核中的核心对象，它负责把「设备号」和「操作函数」真正绑定起来。

#### 定义并初始化
```cpp
struct cdev my_cdev;
cdev_init(&my_cdev, &my_fops);
my_cdev.owner = THIS_MODULE;
```

这里的关键点是：
`file_operations` 在这一步就已经和设备绑定

#### 注册到内核
```cpp
cdev_add(&my_cdev, dev, 1);
```

到这里为止：
内核已经“认识”这个字符设备了。
但用户态还不能访问，因为还没有 /dev 节点

### 创建设备节点（/dev/xxx）

现在基本不会手动 mknod 了，我一般都用 class + device，交给 udev 自动创建设备节点。
```cpp
// 创建 class
struct class *my_class;
my_class = class_create(THIS_MODULE, "mychar");
// 创建设备
struct device *my_device;
my_device = device_create(my_class, NULL, dev, NULL, "mychar0");
```

最终效果：
```
/dev/mychar0
/sys/class/mychar/mychar0
```

卸载时清理
```cpp
device_destroy(my_class, dev);
class_destroy(my_class);
```

### 实现 file_operations（最核心的部分）

file_operations 决定了用户态系统调用是如何一步步走到驱动里的。

#### 最常用的一组回调
```cpp
static const struct file_operations my_fops = {
    .owner          = THIS_MODULE,
    .open           = my_open,
    .release        = my_release,
    .read           = my_read,
    .write          = my_write,
    .unlocked_ioctl = my_ioctl,
    .poll           = my_poll,
    .mmap           = my_mmap,
};
```

并不是所有字符设备都需要这么全，实际项目里一般是按需实现。

#### 几个最常用的回调实现思路
##### open / release
```cpp
static int my_open(struct inode *inode, struct file *filp)
{
    filp->private_data = my_dev;
    return 0;
}


static int my_release(struct inode *inode, struct file *filp)
{
    return 0;
}
```
这是我几乎每个字符设备都会写的模板：

通过 private_data 保存设备上下文  
后续 read/write/ioctl 都能直接拿到

##### read
```cpp
static ssize_t my_read(struct file *filp,
                       char __user *buf,
                       size_t count,
                       loff_t *ppos)
{
    char kbuf[] = "hello\n";


    if (*ppos >= sizeof(kbuf))
        return 0;


    if (copy_to_user(buf, kbuf, sizeof(kbuf)))
        return -EFAULT;


    *ppos += sizeof(kbuf);
    return sizeof(kbuf);
}
```

这里重点注意两点：

一定用 copy_to_user  
正确维护文件偏移 *ppos

##### write

```cpp
static ssize_t my_write(struct file *filp,
                        const char __user *buf,
                        size_t count,
                        loff_t *ppos)
{
    char kbuf[64];


    if (count > sizeof(kbuf))
        count = sizeof(kbuf);


    if (copy_from_user(kbuf, buf, count))
        return -EFAULT;


    return count;
}
```

##### ioctl（控制接口）

```cpp
#define MY_CMD_RESET _IO('M', 0)
#define MY_CMD_SET   _IOW('M', 1, int)


static long my_ioctl(struct file *filp,
                     unsigned int cmd,
                     unsigned long arg)
{
    switch (cmd) {
    case MY_CMD_RESET:
        break;
    case MY_CMD_SET:
        break;
    default:
        return -EINVAL;
    }
    return 0;
}
```

ioctl 我一般用来做：

参数配置  
模式切换  
硬件控制类操作  


##### poll 支持

```cpp
static unsigned int my_poll(struct file *filp, poll_table *wait)
{
    poll_wait(filp, &wq, wait);


    if (data_ready)
        return POLLIN | POLLRDNORM;


    return 0;
}
```

### 阻塞、唤醒与并发控制

字符设备很容易遇到阻塞 IO 的需求，这块在实际项目里非常常见。

#### 常用同步手段

    进程上下文	mutex   
    中断上下文	spinlock   
    阻塞读写	wait_queue   
    poll/select	poll_wait   

##### 阻塞 read 示例
```cpp
wait_event_interruptible(wq, data_ready);
```


### 模块卸载顺序

字符设备卸载时，一般严格按下面顺序来：
```cpp
device_destroy(my_class, dev);
class_destroy(my_class);


cdev_del(&my_cdev);
unregister_chrdev_region(dev, 1);
```
顺序错了，很容易踩坑。

## 总结

    设备号 → cdev → file_operations → /dev 节点 → 用户态访问

核心对象关系：
```
dev_t
 └─ cdev
     └─ file_operations
         └─ open / read / write / ioctl
```
## 进阶方向

inode / file / cdev 之间的真实关系

字符设备如何和中断、workqueue 配合

阻塞 IO 与非阻塞 IO 的设计差异

ioctl 的设计规范和兼容性问题

这一篇更多是打地基，后面再逐个展开。

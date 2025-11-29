---
title: C中二维数组的布局和传参问题
date: 2025-11-27 23:13:07
tags: [C]
---

c中，用malloc创建的“二维数组”，其实并不是真正意义上的数组，因为它的地址是不连续的

上代码：

```c
#include <stdlib.h>
#include <stdio.h>


void func2(int **arr, int rows, int cols) {
    for(int i = 0; i < rows; i++) {
        for(int j = 0; j < cols; j++) {
            printf("%d ", arr[i][j]);
        }
        printf("\n");
    }
}

// 正确创建和传递
int main() {
    int rows = 2, cols = 3;

    int realArray[2][3] = {{4, 5, 6}, {7, 8, 9}};
    
    // 正确创建指针数组
    int **arr = malloc(rows * sizeof(int*));
    for(int i = 0; i < rows; i++) {
        arr[i] = malloc(cols * sizeof(int));
        for(int j = 0; j < cols; j++) {
            arr[i][j] = i * cols + j + 1;
        }
    }
    
    func2(arr, rows, cols);  // 正确！
    func2(realArray, rows, cols);  // 错误！
    
    // 记得释放内存
    for(int i = 0; i < rows; i++) {
        free(arr[i]);
    }
    free(arr);
    
    return 0;
}
```

用GDB分析其内存：
```c
(gdb) n
22          for(int i = 0; i < rows; i++) {
(gdb) n
29          func2(arr, rows, cols);  // 正确！
(gdb) n
1 2 3 
4 5 6 
30          func2(realArray, rows, cols); 
(gdb) print/x &realArray[0][0]
$1 = 0x7fffffffd7a0
(gdb) print/x &realArray[0][1]
$2 = 0x7fffffffd7a4
(gdb) print/x &realArray[0][2]
$3 = 0x7fffffffd7a8
(gdb) print/x &realArray[1][0]
$4 = 0x7fffffffd7ac
(gdb) print/x &realArray[1][1]
$5 = 0x7fffffffd7b0
(gdb) print/x &realArray[1][2]
$6 = 0x7fffffffd7b4
```

我们可以看到，realArray的内存地址是逐渐增加的，连续的。

再来看看arr：
```c
(gdb) print/x &arr[0][0]
$7 = 0x5555555592c0
(gdb) print/x &arr[0][1]
$8 = 0x5555555592c4
(gdb) print/x &arr[0][2]
$9 = 0x5555555592c8
(gdb) print/x &arr[1][0]
$10 = 0x5555555592e0
(gdb) print/x &arr[1][1]
$11 = 0x5555555592e4
(gdb) print/x &arr[1][2]
$12 = 0x5555555592e8
```

可以看出，**行内是连续的，但行间并不连续**（0x5555555592e0 - 0x5555555592c8 ！= 4字节）

所以，在运行时候，会发生coredump:
```bash
zhaoxigang@pc-zxg:~/temp/testarray$ ./test 
1 2 3 
4 5 6 
Segmentation fault (core dumped)
```

实际上，在编译时候就会有个警告：
```bash
zhaoxigang@pc-zxg:~/temp/testarray$ gcc -g test.c -o test
test.c: In function ‘main’:
test.c:30:11: warning: passing argument 1 of ‘func2’ from incompatible pointer type [-Wincompatible-pointer-types]
   30 |     func2(realArray, rows, cols);
      |           ^~~~~~~~~
      |           |
      |           int (*)[3]
test.c:5:18: note: expected ‘int **’ but argument is of type ‘int (*)[3]’
    5 | void func2(int **arr, int rows, int cols) {
      |            ~~~~~~^~~
```

正确做法:  
如果确实要传一个真正的数组，应该指定数组的第二维:
```c
void correct_func2(int rows, int cols, int arr[][cols]) {
    for(int i = 0; i < rows; i++) {
        for(int j = 0; j < cols; j++) {
            printf("%d ", arr[i][j]);
        }
        printf("\n");
    }
}
```

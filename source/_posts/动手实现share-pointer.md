---
title: 动手实现share pointer
date: 2025-11-26 19:51:00
tags: [C++]
---

> share pointer的关键在于动态构造一个变量作为“引用记数”，每一个share pointer类持有其指针. 其次就是重载解引用操作符和箭头操作符

代码如下：
```c
#include <iostream>

template <typename T>
class MySharedPtr
{
public:
    explicit MySharedPtr(T* ptr = nullptr) : raw_ptr_(ptr), count_(ptr ? new size_t(1) : nullptr) {
        // more 
    }

    MySharedPtr(const MySharedPtr& other) : raw_ptr_(other.raw_ptr_), count_(other.count_) {
        if (count_) {
            ++(*count_);
        }
    }

    MySharedPtr& operator=(const MySharedPtr& other) {
        if (this != &other) {
            release();
            raw_ptr_ = other.raw_ptr_;
            count_ = other.count_;
            if (count_) {
                ++(*count_);
            }
        }
        return *this;
    }

    ~MySharedPtr() {
        release();
    }

    T& operator*() const {
        return *raw_ptr_;
    }

    T* operator->() const {
        return raw_ptr_;
    }

    T* get() const {
        return raw_ptr_;
    }

    size_t useCount() const {
        return count_ ? *count_ : 0;
    }

private:
    T* raw_ptr_;
    size_t* count_;

    void release() {
        if (count_ && --(*count_) == 0) {
            delete raw_ptr_;
            delete count_;
        }
    }
};

class MyClass {
public:
    MyClass() { std::cout << "MyClass is constructed!\n"; }
    ~MyClass() { std::cout << "MyClass is deconstructed!\n"; }
    void do_something() { std::cout << "MyClass::do_something() is calling\n"; }
};

int main() {
    {
        MySharedPtr<MyClass> ptr1(new MyClass());
        {
            MySharedPtr<MyClass> ptr2 = ptr1;
            ptr1->do_something();
            ptr2->do_something();
            std::cout << "count is " << ptr1.useCount() << std::endl;
        }
        std::cout << "count is " << ptr1.useCount() << std::endl;
    }

    return 0;
}
```



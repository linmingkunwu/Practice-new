# +加法 -减法 *乘法 **指数 %取余（除法取余数） /除法 //地板除（相除取整数）
a=10
b=15
print(a+b)
print(a-b)
print(a*b)
print(a/b)
print(a%b)
print(a**b)
print(a//b)
print(a%b)
# ==等于（a=b则为真，同下） ！=不等于 > <(大于小于） >= <=(大于等于，小于等于）
c=15
d=20
print(c==d)
print(c!=d)
print(c>d)
print(c<d)
print(c>=d)
print(c<=d)
print('------------and--------------')
# 逻辑运算符 and(同真为真，一假为假） or(一真为真，同假为假） not(如真为假，如假为真）
e=10
f=15
g=15
h=20
print(e+h>=f+g and e<h)
print(e+h>f+g and e<h)
print('-------------or----------------')
print(e+h>f+g or e<h)
print(e+h>f+g or e>h)
print('-------------not---------------')
print(not e>f)
print(not e<f)
print('----------etc----------')
#优先级（）>not>and>or
# += *= etc.
h**=3 # 相当于20*20*20
print(h)
e+=f
print(e)
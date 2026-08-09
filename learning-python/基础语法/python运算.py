#单分支
#  if 代码表达式：
#  代码指令
#  ......
#缩进空四格
'''
sorce=72
if sorce>=72: #不满足直接跳过
   print("成绩通过")
   #可以空四格用pass表示该if语句结束，也可直接顶格也一样表示pass
'''
#双分支
'''
sorce=60
if sorce>=72:
    print('成绩通过')
    pass
else:
    print('不及格')
    pass
'''
#多分支
#notice：elif后面必须有条件和语句
#        else是可选 放在最后
'''
sorce=int(input('please input your sorce:'))
if sorce>90:
    print('your sorce gets A')
    pass
elif sorce>=80:
    print('your sorce gets B')
    pass
elif sorce>=70:
    print('your sorce gets C')
    pass
elif sorce>=60:
    print('your sorce gets D')
    pass
else:
    print('not pass')
'''
#测试 猜拳
'''
import random
inp=int(input('please input your number:'))
computer=random.randint(0,2)
print('电脑出拳：%d'%computer)
if inp>2:
    print('输入错误')
elif inp==0 and computer==2:
    print("win")
elif inp==1 and computer==0:
    print("win")
elif inp==2 and computer==1:
    print("win")
elif inp==computer:
    print("平手")
else:
    print('lose')
'''
'''
# 自己测试 (已修改 运算+嵌套)
import random
inp=int(input('please input your number:'))
computer=random.randint(0,100)
if inp>100:
    print("请重新输入")
if 0<=inp<=100:
    print('电脑出数字：{}'.format(computer))
    if inp>computer:
      print("win")
      pass
    elif inp<computer:
      print("lose")
      pass
    else:
      print("平手")
      pass
else:
    print('请重新输入')
'''
#嵌套时可以每个print后加pass，书写规范

#while循环
#有赋值，有条件
'''
index=1
while index<=100:
    #index=index+1 or
    index+=1
    print(index)
    pass
'''
# 自己测试 (已修改 运算+嵌套+while循环)(整体缩进按tab)
'''
count=1
while count<=10:
    count=count+1
    import random
    inp=int(input('please input your number:'))
    computer=random.randint(0,100)
    if inp>100:
        print("请重新输入")
    if 0<=inp<=100:
        print('电脑出数字：{}'.format(computer))
        if inp>computer:
          print("win")
          pass
        elif inp<computer:
          print("lose")
          pass
        else:
          print("平手")
          pass
    else:
        print('请重新输入')
'''
#99乘法表
'''
i=1
while i<=9:
    j=1
    while j<=i:
        print('%d*%d=%d'%(i,j,i*j),end=' ')
        j+=1    #while需要有变量
    print()
    i+=1
'''
'''
i=9
while i>=1:
    j=1
    while j<=i:
        print('%d*%d=%d'%(i,j,i*j),end='\t')
        j+=1    #while需要有变量
    print()
    i-=1
'''
'''
#打印直角三角形
row=1
while row<=7:
    col=1
    while col<=row:
        print('*',end='\t')
        col+=1
        pass
    print()
    row+=1
'''
#print('这\t个') 这个是空一格 与一个空格相同  \n是空行，与print相同 print('\n')表示空两行
#拓展
'''
row=1
while row<=10: #表示循环十次
    col=1
    while col<=10-row:
        print(' ',end='\t')
        col+=1
        pass
    k=1
    while k<=2*row-1:
        print('*',end='\t')
        k+=1
        pass
    print()
    row+=1
'''
# 测试做等腰梯形 (通过)
'''
row=1
while row<=10:
    col=1
    while col<=10-row:
        print(' ',end='\t')
        col+=1
        pass
    k=1
    while k<=2*row+3:
        print('*',end='\t')
        k+=1
        pass
    print()
    row+=1
'''

#for循环 (在变量中依次取)
'''
tags='hello' #for是将一个变量给赋成另一个变量 再一个个依次读取
for item in tags:
    print(item)
    pass
'''
#rang函数 (括号中数字左闭右开) (包括起始，结束，步长，步长不为零)
'''
for data in range(1,101):
    print(data,end=' ')
    pass
'''
#求累加
'''
sum=0
for data in range(1,101):
    sum+=data
    pass
    #print(sum)
    #print('sum:{}'.format(sum))
print('sum=%d'%sum) #print缩进之后是包括在for函数之中 因此会显示出每一个sum加之后的数
'''
#for使用 (择出偶数)
'''
for data in range(50,401):
    if data%2==0: # 表示除完之后没有余数
        print('是偶数：{}'.format(data))
        pass
    else:
        print('%d是奇数'%data)
'''
# break(退出循环) 与 continue(跳过本次循环) (只能用在循环中)
'''
sum=0
for data in range(1,51):
    if sum>100:
        print('执行到%d就退出来了'%data)
        break
    sum+=data
print('sum=%d'%sum)
'''
'''
for item in range(1,101):
    if item%2==0:
        continue
        pass
    print(item)
    pass
'''
'''
for item in 'i love python':
    if item=='p':
       #break
       continue
    print(item,end=' ')
    pass
'''
#for循环适用于已知循环次数 while循环适用于未知循环次数
#for实现99乘法表
'''
for i in range(1,10):
    for j in range(1,i+1): #相当于内包含 (1,(1,10)) (1,1)无法取值 因此要+1
        print('%d*%d=%d'%(i,j,i*j),end='\t')
        pass
    print()
    pass
'''
#range(3)表示循环3次
#for--else表示一个大循环，当for中的代码被break了，else便不会执行 while--else循环同理
account='linmin'
pwd='123'
for i in range(3):
    zh=input('please input your account:')
    pd=input('please input your password:')
    if account==zh and pwd==pd:
        print('ok')
        break
    pass
else:
    print('error')
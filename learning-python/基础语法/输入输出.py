# 输出 %占位符 也可用中括号【】（？） 也可能是大括号{} 中输入变量 最后加  .format()
#name='miku'
#classpro='pjsk'
#age=18
#print('我的名字是：{}，来自于{}，今年{}岁了'.format(name,classpro,age)) #此方法是加大括号 s->str 字符串
#print('我的名字是%s: 来自[%s] 今年%d岁了'%(name,classpro,age)) #此方法是加中括号 d->digit 数字（0->9）
#print('换\n行')
'''
name='linmin'
QQ=2560044056
loc='中国'
phone=15797951785
print('姓名：{} 年龄是：{}'.format(name,18))
print('QQ: {}'.format(QQ))
print('地点: {}'.format(loc))
print('手机号: {}'.format(phone))
'''
# 另一种方法 print('姓名：%s'%name)

#input
'''
name=input('please input your name:')
loc=input('please input your location:')
phone=input('please input your phone:')
QQ=input('please input your QQ:')

print('姓名：{} 年龄是：{}'.format(name,18))
print('QQ: {}'.format(QQ))
print('地点: {}'.format(loc))
print('手机号: {}'.format(phone))
'''
#利用 print('姓名：%s 年龄:%d岁'%(name,age))时 age input要变为 age=int(input('please input your age’))
# 仅为此情况下数字输入需要



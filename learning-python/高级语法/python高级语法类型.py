#序列是一串按顺序排列的数据集合
#有三种序列类型 字符串 列表 元组
#可支持索引和切片的功能
#特征 第一个正索引为零，指向左端，第一个索引为负数，指向右端
#切片 【高级特性】可根据下标来获取序列对象的任意(或部分)数据
#语法结构 【start:end:step】step默认1
'''
test='python'
print('获取第一个字符%s'%test[0])
for item in test:
    print(item,end=' ')
'''
'''
name='miku'
print('将首字母转换为大写%s'%name.capitalize())
print('将首字母转换为大写:{}'.format(name.capitalize()))#.capitalize函数将首字母转换为大写

a='       hello     '
#b=a.strip()
#print(b)#.strip去除前后空格(开头与结尾)
print(a.lstrip())#去除左边的空格
print(a.rstrip())#去除右边的空格
'''
datastr='i love python'
'''
print(datastr.find('p'))#从零开始数 -1代表该字符不存在
print(datastr.index('p'))#检测字符串中是否包含子字符串 字符不存在会报错
print(datastr.startswith('i'))#检测第一个字符串是否符合
print(datastr.endswith('n'))#检测最后一个字符串是否符合
print(datastr.isdigit())#判断是否为数字
print(datastr.isalpha())#判断是否为字母
print(datastr.isalnum())#判断是否为数字和字母
print(datastr.islower())#判断是否为小写
print(datastr.isupper())#判断是否为大写
print(datastr.isspace())#判断是否都是空白字符(如'  ' \t \n等)
print(datastr.lower())#转为小写
print(datastr.upper())#大写
'''
'''
strmsg='hello world'
print(strmsg[2:5])#左闭右开 从0开始
print(strmsg[:5])
print(strmsg[2:])
print(strmsg[::-1])#倒序输出
'''
#li=[] 空列表
'''
li=[1,2,3,'你好']#你好代表一个数据
print(len(li)) #len函数可以获取列表对象中数据个数
stra='i love python'
print(len(stra))#空格也是一个数据
'''

lista=['abcd',785,12.23,'电脑',True]
''''
print(lista)#输出完整列表
print(lista[0])#输出第一个元素
print(lista[1:3])#从第二个到第三个元素
print(lista[2:])#从第三个到最后
print(lista[::-1])#倒叙
print(lista*3)#多次输出数据(相当于复制)
#数据追加
print(lista)
lista.append(100)
lista.append(200)
print(lista)
#数据插入
lista.insert(2,'这是测试')
print(lista)
'''
'''
rsdata=list(range(10))#强制转换为list对象
#lista.extend(rsdata)#拓展 相当于批量添加
lista.extend([11,22,33,44,'人'])#中括号添加后不显示
print(lista)
'''
'''
#数据修改
print('修改之前',lista)
lista[0]=333.6
print(lista)
'''
#数据删除
listb=list(range(10,50))
#del listb[0]
#del listb[1:3]#批量删除数据
listb.remove(20)#直接输入数据就会去除
listb.pop(1)#输入对应索引删除
print(listb)
#查找数据索引值
print(listb.index(19,10,20))#后面两个表示从10到20这个区间查


#元组序列不可变，创建之后不能做任何修改 用小括号创建元组类型





'''
j=1
y=ag=int(input('please input your age:'))
for age in range(1,2):
    if ag==age:
         print('you get it!')
         break
    elif ag!=age:
        int(input('please guess again :('))
        if ag==age:
            print('you get it!')
            break
        elif int(input('please guess again :(')):
            if ag==age:
                print('you get it!')
                break
            elif ag!=age:
                 int(input('please guess again :('))
                 if ag==age:
                    print('you get it!')
                    break
                 elif input('do you want to retry?(y/n)'):
                      if input('n'):
                           print('alright')
                           break
                      elif input("y"):
                           input('ag')
'''
#修正
'''
times=0
count=3
while times<=3:
    age=int(input('please input your age:'))
    times+=1
    if age==25:
        print('you get it!')
        break
    elif age>25:
        print('please guess again Maybe a little bit big :(')
        pass
    else:
        print('please guess again Maybe a little bit small :(')
    if times==3:
        choose=input('do you want to retry?(y/n)')
        if choose=='y' or choose=='Y':
            times=0
            pass
        elif choose=='n' or choose=='N':
            print('ok alright')
            break
        else:
            print('please input correct word :(')
            pass
'''
#作业2(修改后)
a=float(input('please input your height,notice input meter:'))
b=float(input('please input your weight,notice input kilogram:'))
if a<0 or b<0:
    print('please input correct weight or height :(')
else:
    if 15<=b/(a**2)<18.5:
        print('you need get some nutrition!')
        pass
    elif 18.5<=b/(a**2)<=25:
        print('your BMI is good!')
        pass
    elif 25<=b/(a**2)<=28:
        print('you are a little bit out of weight!')
        pass
    elif 28<=b/(a**2)<=32:
        print('you are overweight!')
        pass
    elif 32<=b/(a**2)<=35:
        print('you are seriously obese!')
        pass
    else:
        print('Maybe I think you are in the tomb,or not a true human?')
        pass












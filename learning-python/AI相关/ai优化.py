import random

def get_random_number():
    return random.randint(0, 100)

def compare_numbers(user_num, computer_num):
    print(f"电脑出数字：{computer_num}")
    if user_num > computer_num:
        print("win")
    elif user_num < computer_num:
        print("lose")
    else:
        print("平手")

for count in range(1, 11):
    while True:
        try:
            inp = int(input(f"这是第 {count} 次游戏，请输入0到100之间的数字："))
            if 0 <= inp <= 100:
                break
            print("数字超出范围，请重新输入！")
        except ValueError:
            print("输入无效，请输入一个数字！")
    computer_num = get_random_number()
    compare_numbers(inp, computer_num)

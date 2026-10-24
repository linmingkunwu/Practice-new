import qrcode

data = "hello world"
filename = "erwelmna.png"
img = qrcode.make(data)
img.save(filename)

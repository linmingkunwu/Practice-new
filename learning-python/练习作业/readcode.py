import cv2

img = cv2.imread("erwelmna.png")
detector = cv2.QRCodeDetector()
data, bbox, straight_qrcode = detector.detectAndDecode(img)
if bbox is not None:
    print(f"二维码数据是: {data}")

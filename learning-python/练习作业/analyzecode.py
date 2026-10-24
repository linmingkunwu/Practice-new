import cv2


def scan():
    capture = cv2.VideoCapture(0)
    while True:
        fetch, frame = capture.read()
        qrCodeDetector = cv2.QRCodeDetector()
        data, bbox, straight_qrcode = qrCodeDetector.detectAndDecode(frame)

        print(data)

        cv2.namedWindow("read-QR", 0)
        cv2.imshow("read-QR", frame)
        key = cv2.waitKey(1)
        if key == 27:
            break


scan()

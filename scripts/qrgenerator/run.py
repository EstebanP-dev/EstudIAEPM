import qrcode
from PIL import Image

url_data = "https://www.linkedin.com/in/j-navia/"
file_name = "linkedin.png"
qr_color = "#ffffff"
final_size = (600, 600)
border_pixels = 20

qr_engine = qrcode.QRCode(
    version=1,
    error_correction=qrcode.constants.ERROR_CORRECT_H,
    box_size=10,
    border=0, 
)

qr_engine.add_data(url_data)
qr_engine.make(fit=True)

qr_img = qr_engine.make_image(fill_color=qr_color, back_color="transparent").convert("RGBA")

inner_size = (final_size[0] - (border_pixels * 2), final_size[1] - (border_pixels * 2))
qr_img = qr_img.resize(inner_size, Image.NEAREST)

canvas = Image.new("RGBA", final_size, (255, 255, 255, 0))
paste_position = (border_pixels, border_pixels)
canvas.paste(qr_img, paste_position, qr_img)

canvas.save(file_name)

print("QR code generated.")
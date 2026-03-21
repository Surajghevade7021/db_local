import requests

BASE_URL = "https://api-backend-equeconnect.equentis.com/offline-payment/request"

TOKEN = ""

headers = {
    "Authorization": f"Bearer eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6MTYwLCJpYXQiOjE3NzAxMTc5NDksImV4cCI6MTc3MDIwNDM0OX0.uPK7UllTzLGHZUbiTdwxfp5ugj9tIWXa4ZFnXFngHW4FczCjYMZtrMeuUPGDpFj2XyEgu1TF8ReSqiwndwA8Eg",
    "Content-Type": "application/json"
}

offline_payment_ids = [7131,7130,7129,7128,7127,7126,7125,7124,7123,7122,7121,7120,7119,7118,7117,7116,7115,7114,7113,7112,7111,7110,7109,7108,7107,7106,7105,7104,7103,7102,7101,7100,7099,7098,7097,7096,7095,7093,7092,7091,7090,7089,7088,7087,7086,7085,7084,7083,7082,7081,7080,7079,7078,7077,7076,7075,7074,7073,7072,7071,7070,7069,7068,7067,7066,7065,7064,7063,7062,7061,7060,7059,7058,7057,7056,7055,7054,7053,7052,7051,7050,7049,7048,7047,7046,7045,7044,7043,7042,7041,7040,7039,7038,7037,7036,7035,7034,7033,7032,7031,7030,7029,7028,7027,7026,7025,7024,7023,7022,7021,7020,7019,7018,7017,7016,7015,7014,7013,7012,7011,7010,7009,7008,7007,7006,7005,7004,7003,7002,7001,7000,6999,6998,6997,6996,6995,6994,6993,6992,6991,6990,6989,6988,6987,6986,6985,6984,6983,6982,6981,6980
]

for offline_payment_id in offline_payment_ids:
    url = f"{BASE_URL}/{offline_payment_id}"
    response = requests.patch(
        url,
        json={"status": "Approved"},
        headers=headers
    )

    if response.status_code == 200:
        print(f"Payment {offline_payment_id} approved")
    else:
        print(
            f"Failed for {offline_payment_id} | "
            f"Status: {response.status_code} | "
            f"Response: {response.text}"
        )
    # exit()

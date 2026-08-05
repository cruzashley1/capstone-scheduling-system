import firebase_init

db = firebase_init.get_db()

# --- TEST: write and read a document to confirm the connection ---
try:
    doc_ref = db.collection("connection_test").document("ping")
    doc_ref.set({"status": "connected"})

    doc = doc_ref.get()
    if doc.exists:
        print("✅ Successfully connected to Firebase!")
        print("Data read back:", doc.to_dict())
    else:
        print("⚠️ Connected, but couldn't read back the test document.")

except Exception as e:
    print("❌ Connection failed. Error details below:")
    print(e)
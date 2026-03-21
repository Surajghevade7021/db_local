
def get_file_path():
    path = input("Enter file path: ").strip()
    return path.strip('"').strip("'")
import sys
import tokenize
import io

def remove_comments(source_path):
    with open(source_path, 'r', encoding='utf-8') as f:
        source = f.read()

    io_obj = io.StringIO(source)
    out = ""
    last_lineno = -1
    last_col = 0
    
    for tok in tokenize.generate_tokens(io_obj.readline):
        token_type = tok[0]
        token_string = tok[1]
        start_line, start_col = tok[2]
        end_line, end_col = tok[3]
        
        if start_line > last_lineno:
            last_col = 0
        
        # Add whitespace where necessary
        if start_col > last_col:
            out += (" " * (start_col - last_col))
            
        # Skip comments
        if token_type == tokenize.COMMENT:
            pass
        else:
            out += token_string
            
        last_lineno = end_line
        last_col = end_col
        
    # Remove lines that are entirely empty or consist only of whitespace
    final_lines = []
    for line in out.split('\n'):
        if line.strip() != '':
            final_lines.append(line)
            
    with open(source_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(final_lines) + '\n')

if __name__ == "__main__":
    remove_comments(r"e:\EcSops\src\payments\refund_payment_updated.py")
    remove_comments(r"e:\EcSops\src\payments\refund_payment.py")
    print("Comments removed successfully.")

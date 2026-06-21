import ballerina/io;

public function repeat() {
    io:fprintln(io:stderr, createSeparator("=", 80));
}

public function createSeparator(string char, int count) returns string {
    string sep = "";
    int i = 0;
    while i < count {
        sep += char;
        i += 1;
    }
    return sep;
}

final _memory = <String, String>{};

String? readStorage(String key) => _memory[key];

void writeStorage(String key, String value) => _memory[key] = value;

void removeStorage(String key) => _memory.remove(key);

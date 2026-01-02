import 'package:flutter/services.dart';

class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Mantém só dígitos
    String digits = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limita a 11 dígitos
    if (digits.length > 11) {
      digits = digits.substring(0, 11);
    }

    var buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if (i == 2 || i == 5) {
        buffer.write('.');
      } else if (i == 8) {
        buffer.write('-');
      }
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

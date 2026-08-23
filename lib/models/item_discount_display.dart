enum ItemDiscountDisplay { compact, detailed, hidden }

ItemDiscountDisplay itemDiscountDisplayFromValue(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case 'detailed':
      return ItemDiscountDisplay.detailed;
    case 'hidden':
      return ItemDiscountDisplay.hidden;
    case 'compact':
    default:
      return ItemDiscountDisplay.compact;
  }
}

extension ItemDiscountDisplayX on ItemDiscountDisplay {
  String get value {
    switch (this) {
      case ItemDiscountDisplay.detailed:
        return 'detailed';
      case ItemDiscountDisplay.hidden:
        return 'hidden';
      case ItemDiscountDisplay.compact:
        return 'compact';
    }
  }

  String get label {
    switch (this) {
      case ItemDiscountDisplay.detailed:
        return 'Detailed';
      case ItemDiscountDisplay.hidden:
        return 'Hidden';
      case ItemDiscountDisplay.compact:
        return 'Compact';
    }
  }
}

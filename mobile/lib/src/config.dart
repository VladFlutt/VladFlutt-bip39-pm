import 'l10n/tr.dart';

/// Где купить ключ Pro. Пустая ссылка — кнопка не показывается.
class ProShop {
  final String name;
  final String url;

  const ProShop(this.name, this.url);
}

/// Магазин, для которого собрано приложение: `--dart-define=STORE=play`.
const store = String.fromEnvironment('STORE');

/// Правила Google Play запрещают вести из приложения к оплате цифровых товаров
/// в обход Play Billing, поэтому в Play-сборке ссылок на покупку нет: ключ, купленный
/// на маркетплейсе или на сайте, по-прежнему вводится на экране Pro.
List<ProShop> get proShops => store == 'play'
    ? <ProShop>[]
    : [
        ProShop('Ozon', ''),
        ProShop('Wildberries', ''),
        ProShop(tr('Сайт ManagerBIP'), 'https://metalogia.vercel.app/#contact'),
      ];

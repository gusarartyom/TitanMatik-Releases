import os
from telegram_notify import send_message as telegram

try:
    telegram(os.environ['UPDATE_ADMIN_CHAT_ID'],
             'TitanMatik: ошибка на этапе ' + os.environ.get('FAILED_STAGE', 'pipeline') +
             '. Предыдущий релиз сохранён, если ошибка произошла до переключения ссылки.\n' + os.environ['RUN_URL'])
except Exception:
    print('Administrator notification failed; check configured integration.')
    raise SystemExit(1)

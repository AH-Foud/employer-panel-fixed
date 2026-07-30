import json, os, time, requests, config
from state import StateMachine
from analytics import Analytics
import sync
import database as db

analytics = Analytics()
state_machine = StateMachine()

def init():
    os.makedirs(config.DATA_DIR, exist_ok=True)
    os.makedirs(config.VOICE_DIR, exist_ok=True)
    db.init_db()
    state_machine.load(None)
    analytics._ensure_file()
    _load_registered()
    _load_sops()
    _load_employers()
    _load_forward_map()

# ===================== API بله =====================

def api_request(method, data=None):
    url = f"{config.BASE_URL}/{method}"
    try:
        if data:
            resp = requests.post(url, json=data, timeout=10)
        else:
            resp = requests.get(url, timeout=10)
        if resp.status_code == 200:
            result = resp.json()
            if result.get("ok"):
                return result.get("result")
        return None
    except Exception as e:
        print(f"[API] Error in {method}: {e}")
        return None

def send_message(chat_id, text, reply_markup=None, parse_mode="Markdown", reply_to_message_id=None):
    data = {"chat_id": chat_id, "text": text, "parse_mode": parse_mode}
    if reply_markup is not None:
        data["reply_markup"] = reply_markup
    if reply_to_message_id is not None:
        data["reply_to_message_id"] = reply_to_message_id
    return api_request("sendMessage", data)

def send_voice(chat_id, voice_file_id, caption=None, reply_markup=None):
    data = {"chat_id": chat_id, "voice": voice_file_id}
    if caption:
        data["caption"] = caption
    if reply_markup is not None:
        data["reply_markup"] = reply_markup
    return api_request("sendVoice", data)

def send_photo(chat_id, file_id, caption=None):
    data = {"chat_id": chat_id, "photo": file_id}
    if caption:
        data["caption"] = caption
    return api_request("sendPhoto", data)

def send_document(chat_id, file_id, caption=None):
    data = {"chat_id": chat_id, "document": file_id}
    if caption:
        data["caption"] = caption
    return api_request("sendDocument", data)

def send_video(chat_id, file_id, caption=None):
    data = {"chat_id": chat_id, "video": file_id}
    if caption:
        data["caption"] = caption
    return api_request("sendVideo", data)

def send_audio(chat_id, file_id, caption=None):
    data = {"chat_id": chat_id, "audio": file_id}
    if caption:
        data["caption"] = caption
    return api_request("sendAudio", data)

def get_file_path(file_id):
    result = api_request("getFile", {"file_id": file_id})
    if result and "file_path" in result:
        return result["file_path"]
    return None

def get_file_url(file_id):
    fp = get_file_path(file_id)
    if fp:
        return f"https://tapi.bale.ai/file/bot{config.BOT_TOKEN}/{fp}"
    return None

def get_voice_file_url(file_id):
    return get_file_url(file_id)

_bot_info_cache = None

def get_bot_info():
    global _bot_info_cache
    if _bot_info_cache:
        return _bot_info_cache
    result = api_request("getMe")
    if result:
        _bot_info_cache = result
        return result
    return None
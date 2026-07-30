# -*- coding: utf-8 -*-
# قة سرور + API + پنل مدیریی

#import json, os, time, threading
from datetime import datetime
import aiofiles

import config
import bot_core
from analytics import Analytics

analytics_bot = bot_core.analytics

# ==================== FastAPI ====================
from fastapi import FastAPI, HTTPException, Query, UploadFile, File, Form
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI�D�tle="پنل مویریز ربات بهل", version="2.1")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ==================== API ====================

@app.get("/api/status")
def api_status():
    registered = bot_core.load_registered()
    sops = bot_core.load_sops()
    msgs = analytics_bot._load()
    bot_info = bot_core.get_bot_info()
    return {
        "online": True,
        "bot_token": config.DOT_TOKEN[:12] + "..." if config.DOT_TOKEN else "تینظن یشد",
        "bot_username": bot_info.get("username", "") if bot_info else "",
        "admin_id": config.ADMIN_ID,
        "total_users": len(registered),
        "total_sops": len(sops),
        "total_messages": len(msgs),
        "last_updated": datetime.now().isoformat()
    }

@app.get("/api/stats")
def api_stats():
    daily = analytics_bot.get_daily_stats()
    weekly = analytics_bot.get_weekly_report()
    registered = bot_core.load_registered()
    sops = bot_core.load_sops()
    msgs = analytics_bot._load()
    msgs_sorted = sorted(msgs, key=lambda m: m.get("timestamp", ""), reverse=True)
    return {
        "daily": daily,
        "weekly": weekly,
        "users_count": len(registered),
        "sops_count": len(sops),
        "messages_count": len(msgs),
        "last_message": msgs_sorted[0] if msgs_sorted else None
    }

@app.get("/api/messages")
def api_messages(limit: int = 100, offset: int = 0, user_id: str = None):
    msgs = analytics_bot._load()
    if user_id:
        msgs = [m for m in msgs if str(m.get("user_id")) == str(user_id)]
    msgs.sort(key=lambda m: m.get("timestamp", ""), reverse=True)
    result = msgs[offset:offset + limit]
    return {"messages": result, "total": len(msgs), "has_more": (offset + limit) < len(msgs)}

@app.get("/api/conversation/{user_id}")
def api_conversation(user_id: str):
    conv = analytics_bot.get_user_conversation(user_id)
    user_info = bot_core.load_registered().get(user_id, {})
    return {"user_id": user_id, "user_name": user_info.get("first_name", "نامشخص"), "phone": user_info.get("phone", ""), "messages": conv}

@app.get("/api/users")
def api_users():
    registered = bot_core.load_registered()
    users = []
    for uid, info in registered.items():
        msgs = analytics_bot._load()
        user_msgs = sum(1 for m in msgs if str(m.get("user_id")) == uid)
        last_msg = None
        for m in reversed(msgs):
            if str(m.get("user_id")) == uid:
                last_msg = m
                break
        users.append({
            "user_id": uid,
            "first_name": info.get("first_name", "کاربر"),
            "phone": info.get("phone", ""),
            "registered_at": info.get("registered_at", ""),
            "total_messages": user_msgs,
            "last_message": last_msg["text"][:80] if last_msg else "",
            "last_message_time": last_msg["timestamp"] if last_msg else ""
        })
    users.sort(key=lambda u: u.get("registered_at", ""), reverse=True)
    return {"users": users, "total": len(users)}

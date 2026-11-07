from __future__ import annotations

from fastapi import APIRouter, File, UploadFile
from fastapi.responses import FileResponse

from app.api.deps import DB, CurrentUser
from app.core.config import get_settings
from app.core.errors import AppError, NotFound
from app.schemas import DeleteAccountRequest, Message, SettingsOut, SettingsUpdate, UserOut, UserUpdate
from app.services import storage, user_service
from app.services.serializers import user_out

router = APIRouter(prefix="/users", tags=["users"])


async def read_limited(file: UploadFile) -> bytes:
    limit = get_settings().max_upload_bytes
    data = await file.read(limit + 1)
    if len(data) > limit:
        raise AppError(413, "file_too_large", f"Image is larger than {limit // (1024 * 1024)} MB.")
    return data


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser):
    return user_out(user)


@router.patch("/me", response_model=UserOut)
def update_me(body: UserUpdate, db: DB, user: CurrentUser):
    return user_out(user_service.update_profile(db, user, body))


@router.post("/avatar", response_model=UserOut)
async def upload_avatar(db: DB, user: CurrentUser, file: UploadFile = File(...)):
    data = await read_limited(file)
    return user_out(user_service.update_avatar(db, user, data, file.content_type))


@router.get("/me/avatar", response_class=FileResponse, responses={200: {"content": {"image/jpeg": {}}}})
def my_avatar(user: CurrentUser):
    path = storage.resolve(user.avatar_path)
    if path is None:
        raise NotFound("Avatar")
    return FileResponse(path, media_type="image/jpeg", headers={"Cache-Control": "private, max-age=86400"})


@router.delete("/me", response_model=Message)
def delete_me(body: DeleteAccountRequest, db: DB, user: CurrentUser):
    user_service.delete_account(db, user, body.password)
    return Message(message="Your account and all associated data have been deleted.")


@router.get("/settings", response_model=SettingsOut)
def get_user_settings(db: DB, user: CurrentUser):
    return user_service.get_settings_row(db, user)


@router.patch("/settings", response_model=SettingsOut)
def patch_user_settings(body: SettingsUpdate, db: DB, user: CurrentUser):
    return user_service.update_settings(db, user, body)

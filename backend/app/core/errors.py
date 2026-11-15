import uuid

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class ApiError(Exception):
    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        error_type: str | None = None,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.error_type = error_type or ("Failure" if status_code >= 500 else "Validation")
        self.headers = headers or {}


def get_request_id(request: Request) -> str:
    return getattr(request.state, "request_id", None) or request.headers.get("X-Request-Id") or str(uuid.uuid4())


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def handle_api_error(request: Request, exc: ApiError) -> JSONResponse:
        req_id = get_request_id(request)
        headers = {"X-Request-Id": req_id, **exc.headers}
        return JSONResponse(
            status_code=exc.status_code,
            headers=headers,
            content={
                "code": exc.code,
                "type": exc.error_type,
                "message": exc.message,
                "requestId": req_id,
            },
        )

    @app.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
        req_id = get_request_id(request)
        return JSONResponse(
            status_code=400,
            headers={"X-Request-Id": req_id},
            content={
                "code": "request.invalid",
                "type": "Validation",
                "message": "Некорректные параметры запроса.",
                "requestId": req_id,
            },
        )

    @app.exception_handler(Exception)
    async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
        req_id = get_request_id(request)
        return JSONResponse(
            status_code=500,
            headers={"X-Request-Id": req_id},
            content={
                "code": "server.unexpected",
                "type": "Failure",
                "message": "Внутренняя ошибка сервера CraftAI.",
                "requestId": req_id,
            },
        )

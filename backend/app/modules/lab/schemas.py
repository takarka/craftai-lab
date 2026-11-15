from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, StringConstraints

Instruction = Annotated[str, StringConstraints(max_length=5000)]
MaterialText = Annotated[str, StringConstraints(min_length=1, max_length=10000)]
Name = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=200)]


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class Permissions(InputModel):
    save_material: bool = False
    search_materials: bool = False


class SkillSelection(InputModel):
    skill_id: str = Field(min_length=1, max_length=100)
    version: int = Field(default=1, ge=1)
    instruction_override: Instruction | None = None


class AgentCreate(InputModel):
    name: Name
    task_type: str = Field(default="custom", min_length=1, max_length=100)
    subject: str = Field(default="", max_length=200)
    grade: str = Field(default="", max_length=100)
    model_id: str | None = Field(default=None, min_length=1, max_length=200)
    instruction: Instruction = ""
    skills: list[SkillSelection] = Field(default_factory=list, max_length=2)
    permissions: Permissions = Field(default_factory=Permissions)


class AgentPatch(InputModel):
    # Missing fields stay unchanged; explicit null is rejected by the service,
    # except model_id, which can be cleared to return an agent to draft state.
    name: Name | None = None
    task_type: str | None = Field(default=None, min_length=1, max_length=100)
    subject: str | None = Field(default=None, max_length=200)
    grade: str | None = Field(default=None, max_length=100)
    model_id: str | None = Field(default=None, min_length=1, max_length=200)
    instruction: Instruction | None = None
    skills: list[SkillSelection] | None = Field(default=None, max_length=2)
    permissions: Permissions | None = None


class AgentCopy(InputModel):
    name: Name | None = None


class CourseProgressInput(InputModel):
    course_version: str = Field(default="0.2", min_length=1, max_length=100)
    current_lesson: int = Field(default=1, ge=1, le=7)
    completed_lessons: list[Annotated[int, Field(ge=1, le=7)]] = Field(default_factory=list, max_length=7)


class MaterialInput(InputModel):
    """Shared validation contract for material writes in LM03."""

    title: Name
    text: MaterialText
    source: str = Field(default="text", pattern="^(text|photo)$")

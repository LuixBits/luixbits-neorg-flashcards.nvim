export const FPS = 30;

export type SceneId =
  | "hook"
  | "storage"
  | "chapters"
  | "current-file"
  | "collection"
  | "tags"
  | "compatibility"
  | "scoring"
  | "outro";

export type SceneDefinition = {
  id: SceneId;
  seconds: number;
  eyebrow: string;
  title: string;
  narration: string;
};

export const SCENES: readonly SceneDefinition[] = [
  {
    id: "hook",
    seconds: 6,
    eyebrow: "THE PROBLEM",
    title: "Your notes already contain the answers.",
    narration: "Flashcards are useful. Rebuilding them in another app every time you take notes is not.",
  },
  {
    id: "storage",
    seconds: 10,
    eyebrow: "THE STORAGE MODEL",
    title: "A .norg file is the database.",
    narration:
      "This plugin treats a plain dot norg file as the database. Each flashcard block keeps the prompt, answer, tags, score, and review date beside your notes.",
  },
  {
    id: "chapters",
    seconds: 13,
    eyebrow: "CHAPTERS",
    title: "One file per chapter. One folder per collection.",
    narration:
      "Put one file per chapter under a flashcards directory. The folder becomes the collection, while each file remains a chapter you can open, edit, move, diff, or sync normally.",
  },
  {
    id: "current-file",
    seconds: 11,
    eyebrow: "FOCUS MODE",
    title: "Study only the chapter you are reading.",
    narration:
      "Open chapter two and run Neorg Flashcard Review File. Only cards from the current file enter the session, so revision stays aligned with the chapter in front of you.",
  },
  {
    id: "collection",
    seconds: 12,
    eyebrow: "COLLECTION MODE",
    title: "Or combine every chapter recursively.",
    narration:
      "Run Neorg Flashcard Review to scan every dot norg file below the collection root. Nested courses and chapters become one review session without merging the source files.",
  },
  {
    id: "tags",
    seconds: 10,
    eyebrow: "CROSS-CUTTING TOPICS",
    title: "Tags connect ideas across chapters.",
    narration:
      "Chapters describe where a card came from. Tags describe what it is about. Review the grammar tag to pull matching cards from several chapter files.",
  },
  {
    id: "compatibility",
    seconds: 10,
    eyebrow: "TWO EDITING MODES",
    title: "Normal Neovim works. Neorg is optional.",
    narration:
      "Normal Neovim can add, review, filter, and rate the cards directly. Add Neorg when you want its syntax, concealing, and note features. The storage format stays dot norg in both modes.",
  },
  {
    id: "scoring",
    seconds: 9,
    eyebrow: "FEEDBACK LOOP",
    title: "Rate the memory, update the source.",
    narration:
      "Reveal the answer, then press one, two, or three. The score and review date are written back to the same card block. No mystery database hiding under the floorboards.",
  },
  {
    id: "outro",
    seconds: 9,
    eyebrow: "LOCAL-FIRST FLASHCARDS",
    title: "Study your notes without leaving Neovim.",
    narration:
      "Current chapter, every chapter, or a tag across all of them. Plain files in Git, a focused review popup, and your notes remain yours.",
  },
] as const;

export const sceneStart = (id: SceneId): number => {
  let seconds = 0;
  for (const scene of SCENES) {
    if (scene.id === id) {
      return seconds * FPS;
    }
    seconds += scene.seconds;
  }
  throw new Error(`Unknown scene: ${id}`);
};

export const sceneDuration = (id: SceneId): number => {
  const scene = SCENES.find((candidate) => candidate.id === id);
  if (!scene) {
    throw new Error(`Unknown scene: ${id}`);
  }
  return scene.seconds * FPS;
};

export const TOTAL_FRAMES = SCENES.reduce((total, scene) => total + scene.seconds * FPS, 0);

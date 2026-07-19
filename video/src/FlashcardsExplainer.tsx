import React, {PropsWithChildren} from "react";
import {
  AbsoluteFill,
  interpolate,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import {fonts, theme} from "./theme";
import {SCENES, SceneId, sceneDuration, sceneStart} from "./timeline";

const sceneById = (id: SceneId) => {
  const scene = SCENES.find((candidate) => candidate.id === id);
  if (!scene) {
    throw new Error(`Unknown scene: ${id}`);
  }
  return scene;
};

const enter = (frame: number, fps: number, delay = 0) =>
  spring({
    frame: Math.max(0, frame - delay),
    fps,
    config: {damping: 18, mass: 0.8, stiffness: 130},
  });

const rise = (frame: number, fps: number, delay = 0, distance = 34): React.CSSProperties => {
  const value = enter(frame, fps, delay);
  return {
    opacity: value,
    transform: `translateY(${(1 - value) * distance}px) scale(${0.97 + value * 0.03})`,
  };
};

const Background: React.FC = () => (
  <AbsoluteFill
    style={{
      backgroundColor: theme.bg,
      backgroundImage: `
        radial-gradient(circle at 12% 16%, rgba(124,247,196,0.11), transparent 31%),
        radial-gradient(circle at 88% 76%, rgba(180,156,255,0.12), transparent 32%),
        linear-gradient(rgba(107,220,255,0.035) 1px, transparent 1px),
        linear-gradient(90deg, rgba(107,220,255,0.035) 1px, transparent 1px)
      `,
      backgroundSize: "auto, auto, 64px 64px, 64px 64px",
    }}
  />
);

const Panel: React.FC<PropsWithChildren<{style?: React.CSSProperties; accent?: string}>> = ({
  children,
  style,
  accent = theme.line,
}) => (
  <div
    style={{
      background: "linear-gradient(145deg, rgba(16,36,58,0.96), rgba(9,24,39,0.96))",
      border: `2px solid ${accent}`,
      borderRadius: 24,
      boxShadow: "0 26px 80px rgba(0,0,0,0.28)",
      ...style,
    }}
  >
    {children}
  </div>
);

const WindowBar: React.FC<{title: string}> = ({title}) => (
  <div
    style={{
      height: 58,
      display: "flex",
      alignItems: "center",
      gap: 12,
      borderBottom: `1px solid ${theme.line}`,
      padding: "0 22px",
      color: theme.muted,
      fontFamily: fonts.mono,
      fontSize: 20,
    }}
  >
    <span style={{color: theme.red}}>●</span>
    <span style={{color: theme.amber}}>●</span>
    <span style={{color: theme.mint}}>●</span>
    <span style={{marginLeft: 12}}>{title}</span>
  </div>
);

const Badge: React.FC<{children: React.ReactNode; color?: string}> = ({children, color = theme.mint}) => (
  <span
    style={{
      display: "inline-flex",
      border: `1px solid ${color}`,
      borderRadius: 999,
      color,
      fontFamily: fonts.mono,
      fontSize: 20,
      fontWeight: 700,
      padding: "8px 14px",
      background: `${color}12`,
    }}
  >
    {children}
  </span>
);

const Command: React.FC<{children: React.ReactNode}> = ({children}) => (
  <div
    style={{
      border: `2px solid ${theme.mint}`,
      borderRadius: 16,
      background: "#06101b",
      color: theme.mint,
      fontFamily: fonts.mono,
      fontSize: 31,
      padding: "19px 24px",
      boxShadow: "0 0 42px rgba(124,247,196,0.11)",
      whiteSpace: "nowrap",
    }}
  >
    {children}
  </div>
);

const Caption: React.FC<{children: string}> = ({children}) => (
  <div
    style={{
      position: "absolute",
      left: 180,
      right: 180,
      bottom: 42,
      minHeight: 62,
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
      textAlign: "center",
      color: theme.text,
      background: "rgba(5,13,23,0.88)",
      border: `1px solid ${theme.line}`,
      borderRadius: 16,
      fontFamily: fonts.sans,
      fontSize: 27,
      lineHeight: 1.35,
      padding: "12px 28px",
    }}
  >
    {children}
  </div>
);

const SceneFrame: React.FC<
  PropsWithChildren<{id: SceneId; compactTitle?: boolean}>
> = ({id, children, compactTitle = false}) => {
  const frame = useCurrentFrame();
  const scene = sceneById(id);
  const duration = sceneDuration(id);
  const opacity = interpolate(frame, [0, 14, duration - 14, duration], [0, 1, 1, 0], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{opacity, padding: "58px 92px 132px"}}>
      <div style={{position: "relative", zIndex: 2}}>
        <div
          style={{
            color: theme.mint,
            fontFamily: fonts.mono,
            fontSize: 22,
            fontWeight: 800,
            letterSpacing: 3.5,
            marginBottom: 12,
          }}
        >
          {scene.eyebrow}
        </div>
        <div
          style={{
            color: theme.text,
            fontFamily: fonts.sans,
            fontSize: compactTitle ? 58 : 68,
            lineHeight: 1.05,
            fontWeight: 830,
            letterSpacing: -2.5,
            maxWidth: 1500,
          }}
        >
          {scene.title}
        </div>
      </div>
      <div style={{flex: 1, position: "relative", marginTop: 36}}>{children}</div>
      <Caption>{scene.narration}</Caption>
    </AbsoluteFill>
  );
};

const Flashcard: React.FC<{answer?: boolean; style?: React.CSSProperties; source?: string}> = ({
  answer = false,
  style,
  source = "chapter-02.norg",
}) => (
  <Panel
    accent={answer ? theme.purple : theme.mint}
    style={{width: 630, height: 385, padding: 30, ...style}}
  >
    <div style={{display: "flex", justifyContent: "space-between", alignItems: "center"}}>
      <Badge color={answer ? theme.purple : theme.mint}>{answer ? "ANSWER" : "PROMPT"}</Badge>
      <span style={{fontFamily: fonts.mono, color: theme.muted, fontSize: 19}}>{source}</span>
    </div>
    <div
      style={{
        color: theme.text,
        fontFamily: fonts.sans,
        fontSize: answer ? 48 : 92,
        fontWeight: 760,
        marginTop: answer ? 55 : 70,
        textAlign: "center",
      }}
    >
      {answer ? "language" : "言語"}
    </div>
    {answer ? (
      <div
        style={{
          color: theme.muted,
          fontFamily: fonts.sans,
          fontSize: 30,
          textAlign: "center",
          marginTop: 18,
        }}
      >
        げんご · noun
      </div>
    ) : null}
  </Panel>
);

const HookScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const arrow = interpolate(frame, [70, 130], [0, 1], {extrapolateLeft: "clamp", extrapolateRight: "clamp"});

  return (
    <SceneFrame id="hook">
      <div style={{height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 70}}>
        <div style={{position: "relative", width: 610, height: 390, ...rise(frame, fps, 10)}}>
          {["chapter-01.norg", "chapter-02.norg", "grammar.norg"].map((name, index) => (
            <Panel
              key={name}
              style={{
                position: "absolute",
                left: index * 55,
                top: index * 48,
                width: 480,
                height: 270,
                padding: 25,
                transform: `rotate(${index * 2 - 2}deg)`,
              }}
            >
              <div style={{fontFamily: fonts.mono, color: theme.purple, fontSize: 23}}>{name}</div>
              <div style={{fontFamily: fonts.mono, color: theme.muted, fontSize: 21, lineHeight: 1.55, marginTop: 26}}>
                * Notes
                <br />
                @flashcard japanese
                <br />
                japanese: 言語
                <br />
                english: language
              </div>
            </Panel>
          ))}
        </div>
        <div
          style={{
            color: theme.mint,
            fontSize: 82,
            opacity: arrow,
            transform: `translateX(${(1 - arrow) * -22}px)`,
          }}
        >
          →
        </div>
        <Flashcard style={rise(frame, fps, 75)} />
      </div>
    </SceneFrame>
  );
};

const StorageScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const lines = [
    ["@flashcard japanese", theme.purple],
    ["japanese: 言語", theme.text],
    ["reading: げんご", theme.text],
    ["english: language", theme.text],
    ["tags: grammar chapter-02", theme.amber],
    ["score: 2", theme.mint],
    ["reviewed: 2026-07-19", theme.cyan],
    ["@end", theme.purple],
  ] as const;

  return (
    <SceneFrame id="storage">
      <div style={{display: "flex", alignItems: "center", justifyContent: "center", gap: 64, height: "100%"}}>
        <Panel style={{width: 880, height: 500, overflow: "hidden", ...rise(frame, fps, 5)}}>
          <WindowBar title="chapter-02.norg — plain text" />
          <div style={{padding: "26px 34px", fontFamily: fonts.mono, fontSize: 27, lineHeight: 1.55}}>
            {lines.map(([line, color], index) => (
              <div key={line} style={{color, ...rise(frame, fps, 18 + index * 8, 14)}}>
                <span style={{color: theme.line, display: "inline-block", width: 55}}>{index + 14}</span>
                {line}
              </div>
            ))}
          </div>
        </Panel>
        <div style={{display: "grid", gap: 18, width: 470}}>
          {[
            ["portable", "move and sync like any note", theme.mint],
            ["inspectable", "no opaque database", theme.purple],
            ["versionable", "Git sees every change", theme.cyan],
          ].map(([label, detail, color], index) => (
            <Panel key={label} accent={color} style={{padding: 24, ...rise(frame, fps, 80 + index * 12)}}>
              <div style={{fontFamily: fonts.mono, color, fontSize: 24, fontWeight: 800}}>{label}</div>
              <div style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 24, marginTop: 6}}>{detail}</div>
            </Panel>
          ))}
        </div>
      </div>
    </SceneFrame>
  );
};

const FileRow: React.FC<{name: string; indent?: number; active?: boolean; count?: number}> = ({
  name,
  indent = 0,
  active = false,
  count,
}) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 12,
      padding: "13px 16px",
      paddingLeft: 18 + indent * 34,
      borderRadius: 12,
      color: active ? theme.text : theme.muted,
      background: active ? "rgba(124,247,196,0.12)" : "transparent",
      border: active ? `1px solid ${theme.mint}` : "1px solid transparent",
      fontFamily: fonts.mono,
      fontSize: 25,
    }}
  >
    <span style={{color: name.endsWith("/") ? theme.amber : theme.purple}}>{name.endsWith("/") ? "◆" : "●"}</span>
    <span>{name}</span>
    {count === undefined ? null : (
      <span style={{marginLeft: "auto", color: theme.mint, fontSize: 20}}>{count} cards</span>
    )}
  </div>
);

const ChaptersScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pulse = interpolate(frame % 60, [0, 30, 60], [0.7, 1, 0.7]);

  return (
    <SceneFrame id="chapters" compactTitle>
      <div style={{display: "flex", justifyContent: "center", alignItems: "center", gap: 70, height: "100%"}}>
        <Panel style={{width: 690, padding: 28, ...rise(frame, fps, 5)}}>
          <FileRow name="flashcards/" />
          <FileRow name="chapter-01.norg" indent={1} count={18} />
          <FileRow name="chapter-02.norg" indent={1} active count={23} />
          <FileRow name="course-b/" indent={1} />
          <FileRow name="chapter-01.norg" indent={2} count={15} />
        </Panel>
        <div style={{display: "grid", gap: 22, width: 650}}>
          <Panel accent={theme.mint} style={{padding: 30, ...rise(frame, fps, 45)}}>
            <Badge>FILE = CHAPTER</Badge>
            <div style={{fontFamily: fonts.sans, color: theme.text, fontSize: 36, fontWeight: 750, marginTop: 20}}>
              chapter-02.norg
            </div>
            <div style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 25, marginTop: 8}}>
              focused study boundary
            </div>
          </Panel>
          <Panel accent={theme.purple} style={{padding: 30, ...rise(frame, fps, 80), boxShadow: `0 0 ${45 * pulse}px rgba(180,156,255,0.13)`}}>
            <Badge color={theme.purple}>FOLDER = COLLECTION</Badge>
            <div style={{fontFamily: fonts.sans, color: theme.text, fontSize: 36, fontWeight: 750, marginTop: 20}}>
              flashcards/
            </div>
            <div style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 25, marginTop: 8}}>
              recursive review boundary
            </div>
          </Panel>
        </div>
      </div>
    </SceneFrame>
  );
};

const CurrentFileScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const showPopup = frame > 82;

  return (
    <SceneFrame id="current-file">
      <div style={{display: "flex", gap: 55, justifyContent: "center", alignItems: "center", height: "100%"}}>
        <div style={{display: "grid", gap: 24, width: 730}}>
          <Panel style={{overflow: "hidden", ...rise(frame, fps, 5)}}>
            <WindowBar title="chapter-02.norg" />
            <div style={{padding: 30, fontFamily: fonts.mono, color: theme.muted, fontSize: 25, lineHeight: 1.55}}>
              <span style={{color: theme.text}}>* Grammar: particles</span>
              <br />
              <br />
              <span style={{color: theme.purple}}>@flashcard japanese</span>
              <br />
              japanese: まで
              <br />
              english: until
              <br />
              tags: grammar particle
              <br />
              <span style={{color: theme.purple}}>@end</span>
            </div>
          </Panel>
          <Command>:NeorgFlashcardReviewFile</Command>
        </div>
        <div style={{opacity: showPopup ? 1 : 0, ...rise(frame, fps, 82)}}>
          <Flashcard source="chapter-02.norg" />
          <div style={{textAlign: "center", marginTop: 18}}>
            <Badge>FILE · 1 / 23</Badge>
          </div>
        </div>
      </div>
    </SceneFrame>
  );
};

const MiniFile: React.FC<{name: string; cards: number; color: string; style?: React.CSSProperties}> = ({
  name,
  cards,
  color,
  style,
}) => (
  <Panel accent={color} style={{width: 380, padding: 26, ...style}}>
    <div style={{fontFamily: fonts.mono, color, fontSize: 25}}>{name}</div>
    <div style={{fontFamily: fonts.sans, color: theme.text, fontSize: 45, fontWeight: 800, marginTop: 20}}>{cards}</div>
    <div style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 22}}>valid cards</div>
  </Panel>
);

const CollectionScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const merge = enter(frame, fps, 95);

  return (
    <SceneFrame id="collection">
      <div style={{height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 48}}>
        <div style={{display: "grid", gap: 18}}>
          <MiniFile name="chapter-01.norg" cards={18} color={theme.mint} style={rise(frame, fps, 10)} />
          <MiniFile name="chapter-02.norg" cards={23} color={theme.purple} style={rise(frame, fps, 30)} />
          <MiniFile name="course-b/chapter-01.norg" cards={15} color={theme.cyan} style={rise(frame, fps, 50)} />
        </div>
        <div style={{color: theme.mint, fontSize: 82, opacity: merge, transform: `scaleX(${merge})`}}>⟹</div>
        <div style={{width: 760, display: "grid", gap: 24, ...rise(frame, fps, 95)}}>
          <Command>:NeorgFlashcardReview</Command>
          <Panel accent={theme.mint} style={{padding: 38, textAlign: "center"}}>
            <div style={{fontFamily: fonts.sans, fontSize: 118, color: theme.text, fontWeight: 850}}>56</div>
            <div style={{fontFamily: fonts.mono, fontSize: 25, color: theme.mint}}>ALL · 1 / 56</div>
            <div style={{fontFamily: fonts.sans, fontSize: 25, color: theme.muted, marginTop: 15}}>
              one session · source files remain separate
            </div>
          </Panel>
        </div>
      </div>
    </SceneFrame>
  );
};

const TagChip: React.FC<{children: string; active?: boolean}> = ({children, active = false}) => (
  <span
    style={{
      border: `1px solid ${active ? theme.amber : theme.line}`,
      color: active ? theme.amber : theme.muted,
      background: active ? "rgba(255,198,109,0.1)" : "transparent",
      borderRadius: 999,
      padding: "8px 13px",
      fontFamily: fonts.mono,
      fontSize: 19,
    }}
  >
    #{children}
  </span>
);

const TagsScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const files = [
    ["chapter-01.norg", ["vocab", "grammar"]],
    ["chapter-02.norg", ["grammar", "particle"]],
    ["course-b/chapter-01.norg", ["grammar", "difficult"]],
  ] as const;

  return (
    <SceneFrame id="tags">
      <div style={{height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 55}}>
        <div style={{display: "grid", gap: 18, width: 700}}>
          {files.map(([name, tags], index) => (
            <Panel key={name} style={{padding: 22, ...rise(frame, fps, 10 + index * 20)}}>
              <div style={{fontFamily: fonts.mono, color: theme.text, fontSize: 24, marginBottom: 16}}>{name}</div>
              <div style={{display: "flex", gap: 10}}>
                {tags.map((tag) => (
                  <TagChip key={tag} active={tag === "grammar"}>{tag}</TagChip>
                ))}
              </div>
            </Panel>
          ))}
        </div>
        <div style={{display: "grid", gap: 22, width: 770, ...rise(frame, fps, 82)}}>
          <Command>:NeorgFlashcardReviewTag grammar</Command>
          <Panel accent={theme.amber} style={{padding: 38, textAlign: "center"}}>
            <Badge color={theme.amber}>TAG: GRAMMAR</Badge>
            <div style={{fontFamily: fonts.sans, color: theme.text, fontSize: 76, fontWeight: 850, marginTop: 28}}>3 chapters</div>
            <div style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 27, marginTop: 8}}>one cross-chapter topic</div>
          </Panel>
        </div>
      </div>
    </SceneFrame>
  );
};

const CompatibilityScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const shared = enter(frame, fps, 70);

  const mode = (title: string, color: string, features: string[], delay: number) => (
    <Panel accent={color} style={{width: 650, padding: 34, ...rise(frame, fps, delay)}}>
      <Badge color={color}>{title}</Badge>
      <div style={{display: "grid", gap: 16, marginTop: 30}}>
        {features.map((feature) => (
          <div key={feature} style={{fontFamily: fonts.sans, color: theme.text, fontSize: 27}}>
            <span style={{color, marginRight: 14}}>✓</span>{feature}
          </div>
        ))}
      </div>
    </Panel>
  );

  return (
    <SceneFrame id="compatibility">
      <div style={{height: "100%", display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 30}}>
        <div style={{display: "flex", gap: 48}}>
          {mode("PLAIN NEOVIM", theme.mint, ["add and review", "tags and scores", "plain-text editing"], 10)}
          {mode("NEOVIM + NEORG", theme.purple, ["the same flashcards", "syntax and concealing", "Neorg note features"], 28)}
        </div>
        <div
          style={{
            opacity: shared,
            display: "flex",
            alignItems: "center",
            gap: 20,
            fontFamily: fonts.mono,
            color: theme.text,
            fontSize: 30,
          }}
        >
          <span style={{color: theme.mint}}>PLAIN NVIM</span>
          <span>→</span>
          <Badge color={theme.amber}>SHARED .NORG FILES</Badge>
          <span>←</span>
          <span style={{color: theme.purple}}>NEORG</span>
        </div>
      </div>
    </SceneFrame>
  );
};

const ScoringScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const revealed = frame > 55;
  const rated = frame > 145;

  return (
    <SceneFrame id="scoring">
      <div style={{height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 62}}>
        <div style={{display: "grid", gap: 18, ...rise(frame, fps, 5)}}>
          <Flashcard answer={revealed} />
          <div style={{display: "flex", gap: 14, justifyContent: "center"}}>
            {[
              ["1", "bad", theme.red],
              ["2", "mid", theme.amber],
              ["3", "good", theme.mint],
            ].map(([key, label, color]) => (
              <div key={key} style={{border: `2px solid ${color}`, color, borderRadius: 13, padding: "12px 20px", fontFamily: fonts.mono, fontSize: 23}}>
                {key} · {label}
              </div>
            ))}
          </div>
        </div>
        <Panel accent={rated ? theme.mint : theme.line} style={{width: 690, overflow: "hidden", ...rise(frame, fps, 75)}}>
          <WindowBar title="chapter-02.norg — writeback" />
          <div style={{padding: 32, fontFamily: fonts.mono, fontSize: 28, lineHeight: 1.65, color: theme.muted}}>
            japanese: 言語
            <br />
            english: language
            <br />
            tags: grammar
            <br />
            <span style={{color: rated ? theme.mint : theme.line}}>score: {rated ? "3" : "_"}</span>
            <br />
            <span style={{color: rated ? theme.cyan : theme.line}}>reviewed: {rated ? "2026-07-19" : "_"}</span>
          </div>
        </Panel>
      </div>
    </SceneFrame>
  );
};

const OutroScene: React.FC = () => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const commands = [
    [":NeorgFlashcardReviewFile", "current chapter"],
    [":NeorgFlashcardReview", "every chapter"],
    [":NeorgFlashcardReviewTag grammar", "one topic everywhere"],
  ] as const;

  return (
    <SceneFrame id="outro">
      <div style={{height: "100%", display: "flex", alignItems: "center", justifyContent: "center", gap: 70}}>
        <div style={{display: "grid", gap: 18, width: 900}}>
          {commands.map(([command, meaning], index) => (
            <Panel key={command} accent={index === 1 ? theme.purple : theme.line} style={{padding: "22px 28px", display: "flex", alignItems: "center", ...rise(frame, fps, 10 + index * 18)}}>
              <span style={{fontFamily: fonts.mono, color: theme.mint, fontSize: 25}}>{command}</span>
              <span style={{fontFamily: fonts.sans, color: theme.muted, fontSize: 23, marginLeft: "auto"}}>{meaning}</span>
            </Panel>
          ))}
        </div>
        <div style={{width: 560, textAlign: "center", ...rise(frame, fps, 70)}}>
          <div style={{fontFamily: fonts.mono, color: theme.purple, fontSize: 28}}>luixbits-neorg-flashcards.nvim</div>
          <div style={{fontFamily: fonts.sans, color: theme.text, fontWeight: 850, fontSize: 72, lineHeight: 1.05, marginTop: 28}}>
            Notes in.
            <br />
            Knowledge out.
          </div>
          <div style={{fontFamily: fonts.mono, color: theme.mint, fontSize: 25, marginTop: 28}}>.norg · local-first · no database</div>
        </div>
      </div>
    </SceneFrame>
  );
};

const scenes: Record<SceneId, React.FC> = {
  hook: HookScene,
  storage: StorageScene,
  chapters: ChaptersScene,
  "current-file": CurrentFileScene,
  collection: CollectionScene,
  tags: TagsScene,
  compatibility: CompatibilityScene,
  scoring: ScoringScene,
  outro: OutroScene,
};

export const FlashcardsExplainer: React.FC = () => (
  <AbsoluteFill style={{backgroundColor: theme.bg, overflow: "hidden"}}>
    <Background />
    {SCENES.map((scene) => {
      const Component = scenes[scene.id];
      return (
        <Sequence key={scene.id} from={sceneStart(scene.id)} durationInFrames={sceneDuration(scene.id)}>
          <Component />
        </Sequence>
      );
    })}
  </AbsoluteFill>
);

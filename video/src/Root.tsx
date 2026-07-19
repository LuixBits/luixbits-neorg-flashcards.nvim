import React from "react";
import {Composition} from "remotion";
import {FlashcardsExplainer} from "./FlashcardsExplainer";
import {FPS, TOTAL_FRAMES} from "./timeline";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="FlashcardsExplainer"
      component={FlashcardsExplainer}
      durationInFrames={TOTAL_FRAMES}
      fps={FPS}
      width={1920}
      height={1080}
    />
  );
};

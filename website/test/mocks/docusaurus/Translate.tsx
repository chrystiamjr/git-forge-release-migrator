import React from 'react';

type TranslateProps = {
  children: React.ReactNode;
};

export default function Translate({ children }: TranslateProps): JSX.Element {
  return <>{children}</>;
}

export function translate(options: { message: string }): string {
  return options.message;
}

export type TranslateFunction = (options: { id: string; message: string }) => string;

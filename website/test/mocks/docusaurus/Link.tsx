import React from 'react';

type LinkProps = {
  to: string;
  className?: string;
  children: React.ReactNode;
};

export default function Link({ to, className, children }: LinkProps): JSX.Element {
  return (
    <a href={to} className={className}>
      {children}
    </a>
  );
}

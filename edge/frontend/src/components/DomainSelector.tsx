import React from "react";
import type { Domain } from "../../../shared/types.js";

const DOMAINS: { value: Domain; label: string }[] = [
  { value: "general", label: "General" },
  { value: "school", label: "School" },
  { value: "business", label: "Business" },
  { value: "coding", label: "Coding" },
  { value: "texting", label: "Texting" },
  { value: "research", label: "Research" },
];

interface Props {
  value: Domain;
  onChange: (v: Domain) => void;
}

export function DomainSelector({ value, onChange }: Props) {
  return (
    <label className="domain">
      <span className="muted">Domain</span>
      <select value={value} onChange={(e) => onChange(e.target.value as Domain)}>
        {DOMAINS.map((d) => (
          <option key={d.value} value={d.value}>{d.label}</option>
        ))}
      </select>
    </label>
  );
}

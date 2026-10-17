import "./style.css";
export const metadata = {
  title: "SecureQuiz · Teacher workspace",
  description: "Create quizzes and review student attempts",
};
export default function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}

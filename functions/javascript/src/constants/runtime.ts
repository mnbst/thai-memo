/**
 * Auth トリガーの実行 SA。
 *
 * 既定の App Engine SA はプロジェクトの Editor を持つので、Go 関数と同じ
 * 専用 SA（terraform/main.tf の functions_runtime）で動かす。
 * "name@" はデプロイ先プロジェクトの SA として解決される。
 */
export const RUNTIME_SERVICE_ACCOUNT = "functions-runtime@";

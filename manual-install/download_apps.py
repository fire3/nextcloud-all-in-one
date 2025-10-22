#!/usr/bin/env python3
"""
Nextcloud应用下载工具
用于从GitHub下载Nextcloud应用的最新版本
"""

import os
import sys
import json
import argparse
import requests
import tarfile
import zipfile
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional, Tuple
import logging

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class NextcloudAppDownloader:
    """Nextcloud应用下载器"""
    
    def __init__(self, apps_dir: str = "nextcloud-apps"):
        self.apps_dir = Path(apps_dir)
        self.apps_dir.mkdir(exist_ok=True)
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Nextcloud-AIO-App-Downloader/1.0'
        })
        
        # 核心应用列表
        self.core_apps = [
            "notify_push", "files_texteditor", "richdocuments", 
            "talk", "whiteboard", "clamav", "fulltextsearch"
        ]
        
        # 下载统计
        self.stats = {
            'successful': 0,
            'failed': 0,
            'failed_apps': []
        }
    
    def get_app_repo_info(self, app_id: str) -> Optional[Dict]:
        """获取应用的GitHub仓库信息"""
        try:
            # 尝试几种可能的仓库名称格式
            possible_repos = [
                f"nextcloud/{app_id}",
                f"nextcloud/apps_{app_id}",
                f"nextcloud-releases/{app_id}"
            ]
            
            for repo_name in possible_repos:
                url = f"https://api.github.com/repos/{repo_name}"
                logger.info(f"检查仓库: {repo_name}")
                
                response = self.session.get(url)
                if response.status_code == 200:
                    repo_info = response.json()
                    logger.info(f"找到仓库: {repo_name}")
                    return repo_info
                elif response.status_code == 404:
                    continue
                else:
                    logger.warning(f"API请求失败: {response.status_code}")
                    continue
            
            logger.error(f"未找到应用 {app_id} 的GitHub仓库")
            return None
            
        except Exception as e:
            logger.error(f"获取仓库信息时出错: {e}")
            return None
    
    def get_latest_release(self, repo_full_name: str) -> Optional[Dict]:
        """获取仓库的最新发布版本"""
        try:
            url = f"https://api.github.com/repos/{repo_full_name}/releases/latest"
            logger.info(f"获取最新版本: {repo_full_name}")
            
            response = self.session.get(url)
            if response.status_code == 200:
                release_info = response.json()
                logger.info(f"找到最新版本: {release_info.get('tag_name', 'unknown')}")
                return release_info
            else:
                logger.error(f"获取最新版本失败: {response.status_code}")
                return None
                
        except Exception as e:
            logger.error(f"获取最新版本时出错: {e}")
            return None
    
    def download_file(self, url: str, file_path: Path) -> bool:
        """下载文件"""
        try:
            logger.info(f"开始下载: {url}")
            
            response = self.session.get(url, stream=True)
            response.raise_for_status()
            
            file_path.parent.mkdir(parents=True, exist_ok=True)
            
            with open(file_path, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            
            logger.info(f"下载完成: {file_path}")
            return True
            
        except Exception as e:
            logger.error(f"下载文件失败: {e}")
            return False
    
    def extract_archive(self, archive_path: Path, extract_to: Path) -> bool:
        """解压归档文件"""
        try:
            logger.info(f"解压文件: {archive_path}")
            
            if archive_path.suffix == '.gz' and archive_path.stem.endswith('.tar'):
                with tarfile.open(archive_path, 'r:gz') as tar:
                    tar.extractall(extract_to)
            elif archive_path.suffix == '.zip':
                with zipfile.ZipFile(archive_path, 'r') as zip_file:
                    zip_file.extractall(extract_to)
            else:
                logger.error(f"不支持的归档格式: {archive_path}")
                return False
            
            logger.info(f"解压完成: {extract_to}")
            return True
            
        except Exception as e:
            logger.error(f"解压文件失败: {e}")
            return False
    
    def download_app(self, app_id: str) -> bool:
        """下载单个应用"""
        try:
            logger.info(f"开始下载应用: {app_id}")
            
            # 获取仓库信息
            repo_info = self.get_app_repo_info(app_id)
            if not repo_info:
                self.stats['failed'] += 1
                self.stats['failed_apps'].append(app_id)
                return False
            
            repo_full_name = repo_info['full_name']
            
            # 获取最新版本
            release_info = self.get_latest_release(repo_full_name)
            if not release_info:
                self.stats['failed'] += 1
                self.stats['failed_apps'].append(app_id)
                return False
            
            # 查找下载链接
            download_url = None
            filename = None
            
            for asset in release_info.get('assets', []):
                asset_name = asset['name']
                if asset_name.endswith(('.tar.gz', '.zip')):
                    download_url = asset['browser_download_url']
                    filename = asset_name
                    break
            
            if not download_url:
                # 如果没有assets，尝试使用源码包
                download_url = release_info.get('tarball_url')
                if download_url:
                    filename = f"{app_id}-{release_info['tag_name']}.tar.gz"
            
            if not download_url:
                logger.error(f"未找到 {app_id} 的下载链接")
                self.stats['failed'] += 1
                self.stats['failed_apps'].append(app_id)
                return False
            
            # 创建应用目录
            app_dir = self.apps_dir / app_id
            app_dir.mkdir(exist_ok=True)
            
            # 下载文件
            file_path = app_dir / filename
            if not self.download_file(download_url, file_path):
                self.stats['failed'] += 1
                self.stats['failed_apps'].append(app_id)
                return False
            
            # 保存应用信息
            app_info = {
                'id': app_id,
                'name': repo_info.get('name', app_id),
                'version': release_info['tag_name'],
                'description': repo_info.get('description', ''),
                'downloaded_file': filename,
                'download_url': download_url,
                'repo_url': repo_info['html_url'],
                'download_date': datetime.now().isoformat()
            }
            
            info_file = app_dir / 'info.json'
            with open(info_file, 'w', encoding='utf-8') as f:
                json.dump(app_info, f, indent=2, ensure_ascii=False)
            
            logger.info(f"应用 {app_id} 下载成功")
            self.stats['successful'] += 1
            return True
            
        except Exception as e:
            logger.error(f"下载应用 {app_id} 时出错: {e}")
            self.stats['failed'] += 1
            self.stats['failed_apps'].append(app_id)
            return False
    
    def download_apps(self, app_list: List[str]) -> Dict:
        """批量下载应用"""
        logger.info(f"开始批量下载 {len(app_list)} 个应用")
        
        for app_id in app_list:
            try:
                self.download_app(app_id)
            except Exception as e:
                logger.error(f"下载应用 {app_id} 时发生未预期的错误: {e}")
                self.stats['failed'] += 1
                if app_id not in self.stats['failed_apps']:
                    self.stats['failed_apps'].append(app_id)
        
        # 生成下载报告
        report = {
            'download_date': datetime.now().isoformat(),
            'total_apps': len(app_list),
            'successful_downloads': self.stats['successful'],
            'failed_downloads': self.stats['failed'],
            'failed_apps': self.stats['failed_apps'],
            'success_rate': f"{(self.stats['successful'] / len(app_list) * 100):.1f}%" if app_list else "0%"
        }
        
        # 保存报告
        report_file = self.apps_dir / 'download-report.json'
        with open(report_file, 'w', encoding='utf-8') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        logger.info(f"下载完成: 成功 {self.stats['successful']}, 失败 {self.stats['failed']}")
        return report

def main():
    parser = argparse.ArgumentParser(description='Nextcloud应用下载工具')
    parser.add_argument('--custom-apps', type=str, help='自定义应用列表，用逗号分隔')
    parser.add_argument('--skip-core', action='store_true', help='跳过核心应用')
    parser.add_argument('--apps-dir', type=str, default='nextcloud-apps', help='应用下载目录')
    parser.add_argument('--verbose', '-v', action='store_true', help='详细输出')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    downloader = NextcloudAppDownloader(args.apps_dir)
    
    # 确定要下载的应用列表
    apps_to_download = []
    
    if args.custom_apps:
        custom_apps = [app.strip() for app in args.custom_apps.split(',') if app.strip()]
        apps_to_download.extend(custom_apps)
    
    if not args.skip_core:
        apps_to_download.extend(downloader.core_apps)
    
    # 去重
    apps_to_download = list(set(apps_to_download))
    
    if not apps_to_download:
        logger.error("没有指定要下载的应用")
        sys.exit(1)
    
    logger.info(f"将要下载的应用: {', '.join(apps_to_download)}")
    
    # 开始下载
    report = downloader.download_apps(apps_to_download)
    
    # 输出结果
    print(f"\n下载完成!")
    print(f"成功下载: {report['successful_downloads']} 个应用")
    print(f"下载失败: {report['failed_downloads']} 个应用")
    print(f"成功率: {report['success_rate']}")
    
    if report['failed_apps']:
        print(f"失败的应用: {', '.join(report['failed_apps'])}")
    
    # 如果有失败的应用，返回非零退出码
    if report['failed_downloads'] > 0:
        sys.exit(1)

if __name__ == '__main__':
    main()
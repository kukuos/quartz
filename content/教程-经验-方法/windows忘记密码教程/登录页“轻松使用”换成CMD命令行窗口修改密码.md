---
title: windows登录页“轻松使用”换成CMD命令行窗口修改密码
---
##
![[windows命令修改密码.mp4]]

下面是文字教程

第一步
再登录界面一直长按着"Shift按键"同时点击桌面"右下角的重启"直到蓝色的界面再松开按键。
![[Pasted image 20260809015352.png]]
![[Pasted image 20260809015542.png|521]]
如果期间出现蓝屏、重启电脑时重新再登录界面按照上面的方法进入。

##
第二步
在”疑难解答“里进入”高级选项“找到"命令提示"
![[Pasted image 20260809020142.png|578]]


##
第三步
先执行下面的命令备份复制文件，以防损坏文件时恢复。
`copy C:\windows\system32\utilman.exe C:\Windows\system32\utilman.exe.bak`

再执行这个命令，会出现Yes/No时输入"yes"回车
`copy C:\windows\system32\cmd.exe C:\windows\system32\utilman.exe`

下面是示例，成功会显示两个"已复制"
![[Pasted image 20260809020526.png|700]]


##
第四步
关闭这个命令窗口，返回蓝色界面选择"继续"来重启电脑
![[Pasted image 20260809020838.png]]

在登录页的右下角找到小人的按钮“辅助功能”会弹出命令窗口

![[Pasted image 20260809021016.png]]

![[Pasted image 20260809021637.png]]

输入命令
net localgroup administrators

net user 要修改的用户名 *
注意这里的 “*” 是小写的，输入密码不会显示出密码，输完之后直接按回车在确认输入一遍密码回车确认。

##
第五步
关闭命令窗口，输入修改的密码登录
